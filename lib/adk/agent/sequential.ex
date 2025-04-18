defmodule Adk.Agent.Sequential do
  @moduledoc """
  Implements a sequential workflow agent per the Adk pattern.

  This agent executes a series of steps (tools, functions, or transforms) in order, passing the output of each step as input to the next. Steps are defined in the agent's configuration. Supports logging, memory integration, and error propagation. Implements the `Adk.Agent` behaviour.

  Extension points:
  - Add new step types by extending `execute_step/4`.
  - Customize event logging by overriding helper functions.
  - See https://google.github.io/adk-docs/Agent/Workflow-agents for design rationale.
  """
  alias Adk.Memory
  # alias Adk.Event # Removed - Event struct used directly via Adk.Event
  alias Adk.ToolRegistry
  require UUID
  require Logger
  @behaviour Adk.Agent

  # --- Structs ---

  defmodule Config do
    @moduledoc """
    Configuration struct for the Sequential Agent.
    """
    @enforce_keys [:name, :steps]
    defstruct [
      :name,
      # List of step maps (e.g., %{type: "tool", ...}, %{type: "function", ...})
      :steps,
      # Optional: List of tool names (strings or atoms) relevant to this agent
      tools: [],
      # Optional: Session ID for context, managed externally
      session_id: nil,
      # Optional: Invocation ID for context, managed externally
      invocation_id: nil
    ]
  end

  # --- Public API ---

  @doc """
  Creates a new Sequential agent config struct after validation.
  """
  def new(config_map) when is_map(config_map) do
    validate_and_build_config(config_map)
  end

  @doc """
  Executes the sequential workflow defined by the agent configuration struct.

  This function implements the core logic of running steps sequentially,
  passing the output of one step as input to the next.

  It relies on `session_id` and `invocation_id` being potentially set
  in the `%Config{}` struct by the caller (e.g., `Adk.Agent.Server`)
  for logging and context.
  """
  @impl Adk.Agent
  def run(%Config{} = config, initial_input) do
    # Use session/invocation IDs from config or generate defaults if missing
    session_id = config.session_id || "stateless-session-#{UUID.uuid4()}"
    invocation_id = config.invocation_id || "stateless-invocation-#{UUID.uuid4()}"
    # Log initial input using the provided context
    log_event(:user, initial_input, config, session_id, invocation_id)

    # The accumulator holds {:ok | :error, latest_output}
    initial_acc = {:ok, initial_input}

    result =
      Enum.reduce_while(config.steps, initial_acc, fn step, {:ok, current_input} ->
        case execute_step(step, current_input, config, session_id, invocation_id) do
          {:ok, step_output} ->
            {:cont, {:ok, step_output}}

          {:error, reason} ->
            log_event(:error, reason, config, session_id, invocation_id)
            {:halt, {:error, reason}}
        end
      end)

    # Log final output or error
    case result do
      {:ok, final_output} ->
        log_event(:agent, final_output, config, session_id, invocation_id)
        {:ok, %{output: final_output}}

      {:error, reason} ->
        # Error already logged within reduce_while
        {:error, reason}

      # Handle halt case (which should contain the error tuple)
      {:halt, error_tuple} ->
        # Error already logged within reduce_while
        error_tuple
    end
  end

  @doc """
  Start a linked process for this agent.
  This delegates to Adk.Agent.Server.start_link/2.
  """
  def start_link(config_map, opts \\ []) when is_map(config_map) do
    with {:ok, config} <- new(config_map) do
      Adk.Agent.Server.start_link(config, opts)
    end
  end

  # --- Private Functions ---

  # Config Validation
  defp validate_and_build_config(config_map) do
    required_keys = [:name, :steps]
    missing_keys = Enum.filter(required_keys, &(!Map.has_key?(config_map, &1)))

    if !Enum.empty?(missing_keys) do
      {:error, {:invalid_config, :missing_keys, missing_keys}}
    else
      try do
        # Set defaults for optional fields
        defaults = %{tools: []}
        config_with_defaults = Map.merge(defaults, config_map)
        config = struct!(Config, config_with_defaults)

        with :ok <- validate_steps(config.steps) do
          {:ok, config}
        else
          {:error, reason} -> {:error, reason}
        end
      rescue
        ArgumentError ->
          {:error, {:invalid_config, :struct_conversion_failed, config_map}}

        e ->
          {:error, {:invalid_config, :unexpected_error, e}}
      end
    end
  end

  defp validate_steps(steps) when not is_list(steps) do
    {:error, {:invalid_config, :steps_not_a_list, steps}}
  end

  defp validate_steps(steps) do
    # Basic validation: Ensure each step is a map with a 'type'
    Enum.reduce_while(steps, :ok, fn step, :ok ->
      if is_map(step) and Map.has_key?(step, :type) do
        {:cont, :ok}
      else
        {:halt, {:error, {:invalid_config, :invalid_step_format, step}}}
      end
    end)
    |> case do
      :ok -> :ok
      # Propagate the halt value
      {:error, reason} -> reason
    end
  end

  # Execute a single step based on its type
  defp execute_step(
         %{type: "tool", tool: tool_name_str, params: params},
         # Tool steps often ignore direct input
         _input,
         %Config{} = config,
         session_id,
         invocation_id
       ) do
    # Keep as string
    tool_name = tool_name_str

    context = %{
      session_id: session_id,
      invocation_id: invocation_id,
      # Sequential agent doesn't generate tool_call_ids
      tool_call_id: nil
    }

    case ToolRegistry.execute_tool(tool_name, params, context) do
      {:ok, result} ->
        tool_result_map = %{tool_call_id: nil, name: tool_name, content: result, status: :ok}
        log_tool_result_event(config, session_id, invocation_id, tool_result_map)
        {:ok, result}

      {:error, reason} ->
        error_content = "Error executing tool '#{tool_name}': #{inspect(reason)}"

        tool_result_map = %{
          tool_call_id: nil,
          name: tool_name,
          content: error_content,
          status: :error
        }

        log_tool_result_event(config, session_id, invocation_id, tool_result_map)
        {:error, {:step_execution_error, :tool, tool_name, reason}}
    end
  end

  defp execute_step(
         %{type: "function", function: function} = step_config,
         input,
         %Config{} = config,
         session_id,
         invocation_id
       )
       when is_function(function, 1) do
    try do
      result = function.(input)
      log_agent_step_event(config, session_id, invocation_id, step_config, input, result)
      {:ok, result}
    rescue
      e ->
        reason = {:step_execution_error, :function, inspect(function), e}

        log_agent_step_event(
          config,
          session_id,
          invocation_id,
          step_config,
          input,
          reason,
          :error
        )

        {:error, reason}
    end
  end

  defp execute_step(
         %{type: "transform", transform: transform_fn} = step_config,
         input,
         %Config{} = config,
         session_id,
         invocation_id
       )
       when is_function(transform_fn, 2) do
    case Memory.get_full_state(:in_memory, session_id) do
      {:ok, memory_state} ->
        try do
          result = transform_fn.(input, memory_state)
          log_agent_step_event(config, session_id, invocation_id, step_config, input, result)
          {:ok, result}
        rescue
          e ->
            reason = {:step_execution_error, :transform, inspect(transform_fn), e}

            log_agent_step_event(
              config,
              session_id,
              invocation_id,
              step_config,
              input,
              reason,
              :error
            )

            {:error, reason}
        end

      {:error, reason} ->
        mem_reason = {:memory_error, :get_full_state_failed, reason}

        log_agent_step_event(
          config,
          session_id,
          invocation_id,
          step_config,
          input,
          mem_reason,
          :error
        )

        {:error, mem_reason}
    end
  end

  defp execute_step(unknown_step, input, %Config{} = config, session_id, invocation_id) do
    Logger.error(
      "[#{session_id}/#{invocation_id}] Unknown step type encountered in Sequential Agent: #{inspect(unknown_step)}"
    )

    reason = {:step_execution_error, :unknown_type, unknown_step}
    log_agent_step_event(config, session_id, invocation_id, unknown_step, input, reason, :error)
    {:error, reason}
  end

  # --- Helper Functions for Logging Events ---

  # Pass config, session_id, invocation_id explicitly
  defp log_tool_result_event(_config, session_id, invocation_id, tool_result_map) do
    event_opts = [
      author: :tool,
      session_id: session_id,
      invocation_id: invocation_id,
      # Result is in tool_results
      content: nil,
      tool_results: [tool_result_map]
    ]

    case Memory.add_message(:in_memory, session_id, event_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "[#{session_id}/#{invocation_id}] Failed to log tool result event for tool #{tool_result_map[:name]}: #{inspect(reason)}"
        )

        :error
    end
  end

  # Pass config, session_id, invocation_id explicitly
  defp log_agent_step_event(
         _config,
         session_id,
         invocation_id,
         step_config,
         input,
         output_or_error,
         status \\ :ok
       ) do
    content = %{
      step_type: Map.get(step_config, :type),
      # Avoid logging functions
      step_details: Map.drop(step_config, [:type, :function, :transform]),
      input: input,
      status: status,
      output: if(status == :ok, do: output_or_error, else: nil),
      # Inspect error
      error: if(status == :error, do: inspect(output_or_error), else: nil)
    }

    event_opts = [
      author: :agent,
      session_id: session_id,
      invocation_id: invocation_id,
      content: content
    ]

    case Memory.add_message(:in_memory, session_id, event_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "[#{session_id}/#{invocation_id}] Failed to log agent step event for step #{inspect(step_config)}: #{inspect(reason)}"
        )

        :error
    end
  end

  # Pass config, session_id, invocation_id explicitly
  defp log_event(author, content, _config, session_id, invocation_id) do
    event_opts = [
      author: author,
      content: content,
      session_id: session_id,
      invocation_id: invocation_id
    ]

    case Memory.add_message(:in_memory, session_id, event_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "[#{session_id}/#{invocation_id}] Failed to log #{author} event: #{inspect(reason)}"
        )

        :error
    end
  end
end
