defmodule Adk.Agents.Sequential do
  @moduledoc """
  A sequential agent that executes a series of steps in order.
  """
  use GenServer
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
      tools: []
    ]
  end

  defmodule State do
    @moduledoc """
    Internal state struct for the Sequential Agent GenServer.
    """
    @enforce_keys [:session_id, :config]
    defstruct [
      :session_id,
      # Holds the %Config{} struct
      :config
      # current_step: 0 # Removed, step execution is stateless within run_steps
    ]
  end

  # --- Agent API ---

  @impl Adk.Agent
  def run(agent, input), do: Adk.Agent.run(agent, input)

  # --- GenServer Callbacks ---

  @impl GenServer
  def init(config_map) when is_map(config_map) do
    with {:ok, config} <- validate_and_build_config(config_map) do
      session_id = UUID.uuid4()
      state = %State{session_id: session_id, config: config}
      {:ok, state}
    else
      # Propagate descriptive error tuple
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  @spec handle_call({:run, any()}, any(), State.t()) ::
          {:reply, {:ok, map()} | {:error, term()}, State.t()}
  def handle_call({:run, input}, _from, %State{} = state) do
    invocation_id = UUID.uuid4()

    # Log initial input as an event
    user_event_opts = [
      author: :user,
      content: input,
      session_id: state.session_id,
      invocation_id: invocation_id
    ]

    case Memory.add_message(:in_memory, state.session_id, user_event_opts) do
      :ok ->
        # Process the input through each step
        case run_steps(input, state, invocation_id) do
          # run_steps now returns {:ok, output} | {:error, reason}
          {:ok, output} ->
            # The final output is in the `output` map key
            # State doesn't change during run
            {:reply, {:ok, output}, state}

          {:error, reason} ->
            # Reason should be a descriptive tuple
            # State doesn't change during run
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        error_tuple = {:error, {:memory_error, :add_message_failed, {:user_input, reason}}}
        {:reply, error_tuple, state}
    end
  end

  # --- Private Functions ---

  # Config Validation
  defp validate_and_build_config(config_map) do
    # 1. Check for required keys first
    required_keys = [:name, :steps]
    missing_keys = Enum.filter(required_keys, &(!Map.has_key?(config_map, &1)))

    if !Enum.empty?(missing_keys) do
      {:error, {:invalid_config, :missing_keys, missing_keys}}
    else
      # 2. Attempt struct conversion (should succeed for required keys now)
      try do
        # No defaults to set here
        config = struct!(Config, config_map)

        # 3. Perform further validations
        with :ok <- validate_steps(config.steps) do
          {:ok, config}
        else
          # Capture the first validation error
          {:error, reason} -> {:error, reason}
        end
      rescue
        # Catch ArgumentError from struct! if types are wrong for non-enforced keys
        ArgumentError ->
          {:error, {:invalid_config, :struct_conversion_failed, config_map}}

        # Catch any other unexpected error during struct creation/validation
        e ->
          {:error, {:invalid_config, :unexpected_error, e}}
      end
    end
  end

  defp validate_steps(steps) when not is_list(steps) do
    {:error, {:invalid_config, :steps_not_a_list, steps}}
  end

  defp validate_steps(_steps) do
    # Optionally, add validation for each step's structure here
    # For now, just ensure it's a list
    :ok
  end

  # Step Execution Logic
  @spec run_steps(any(), State.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defp run_steps(initial_input, %State{} = state, invocation_id) do
    # The accumulator holds {:ok | :error, latest_output}
    initial_acc = {:ok, initial_input}

    Enum.reduce_while(state.config.steps, initial_acc, fn step, {:ok, current_input} ->
      case execute_step(step, current_input, state, invocation_id) do
        {:ok, step_output} ->
          # Continue with the new output
          {:cont, {:ok, step_output}}

        {:error, reason} ->
          # Halt with the error
          {:halt, {:error, reason}}
      end
    end)
    # Wrap final result or error
    |> case do
      {:ok, final_output} -> {:ok, %{output: final_output}}
      {:error, reason} -> {:error, reason}
      # Handle halt case explicitly if needed, though reduce_while returns the halt value directly
      {:halt, error_tuple} -> error_tuple
    end
  end

  # Execute a single step based on its type
  @spec execute_step(map(), any(), State.t(), String.t()) :: {:ok, any()} | {:error, term()}
  defp execute_step(
         %{type: "tool", tool: tool_name_str, params: params},
         # Tool steps often ignore direct input, relying on params or memory
         _input,
         %State{} = state,
         invocation_id
       ) do
    # Keep as string for ToolRegistry
    tool_name = tool_name_str

    context = %{
      session_id: state.session_id,
      invocation_id: invocation_id,
      # Sequential agent doesn't generate tool_call_ids
      tool_call_id: nil
    }

    case ToolRegistry.execute_tool(tool_name, params, context) do
      {:ok, result} ->
        # Log tool result event
        tool_result_map = %{
          tool_call_id: nil,
          name: tool_name,
          content: result,
          status: :ok
        }

        log_tool_result_event(state, invocation_id, tool_result_map)
        {:ok, result}

      {:error, reason} ->
        # Log tool error event
        error_content = "Error executing tool '#{tool_name}': #{inspect(reason)}"

        tool_result_map = %{
          tool_call_id: nil,
          name: tool_name,
          content: error_content,
          status: :error
        }

        log_tool_result_event(state, invocation_id, tool_result_map)
        {:error, {:step_execution_error, :tool, tool_name, reason}}
    end
  end

  defp execute_step(
         %{type: "function", function: function} = step_config,
         input,
         %State{} = state,
         invocation_id
       )
       when is_function(function, 1) do
    try do
      result = function.(input)
      log_agent_step_event(state, invocation_id, step_config, input, result)
      {:ok, result}
    rescue
      e ->
        reason = {:step_execution_error, :function, inspect(function), e}
        log_agent_step_event(state, invocation_id, step_config, input, reason, :error)
        {:error, reason}
    end
  end

  defp execute_step(
         %{type: "transform", transform: transform_fn} = step_config,
         input,
         %State{} = state,
         invocation_id
       )
       when is_function(transform_fn, 2) do
    case Memory.get_full_state(:in_memory, state.session_id) do
      {:ok, memory_state} ->
        try do
          result = transform_fn.(input, memory_state)
          log_agent_step_event(state, invocation_id, step_config, input, result)
          {:ok, result}
        rescue
          e ->
            reason = {:step_execution_error, :transform, inspect(transform_fn), e}
            log_agent_step_event(state, invocation_id, step_config, input, reason, :error)
            {:error, reason}
        end

      {:error, reason} ->
        mem_reason = {:memory_error, :get_full_state_failed, reason}
        log_agent_step_event(state, invocation_id, step_config, input, mem_reason, :error)
        {:error, mem_reason}
    end
  end

  defp execute_step(unknown_step, input, %State{} = state, invocation_id) do
    Logger.error("Unknown step type encountered in Sequential Agent: #{inspect(unknown_step)}")
    reason = {:step_execution_error, :unknown_type, unknown_step}
    log_agent_step_event(state, invocation_id, unknown_step, input, reason, :error)
    {:error, reason}
  end

  # --- Helper Functions for Logging Events ---

  @spec log_tool_result_event(State.t(), String.t(), map()) :: :ok | :error
  defp log_tool_result_event(state, invocation_id, tool_result_map) do
    event_opts = [
      author: :tool,
      session_id: state.session_id,
      invocation_id: invocation_id,
      # Result is in tool_results
      content: nil,
      tool_results: [tool_result_map]
    ]

    case Memory.add_message(:in_memory, state.session_id, event_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to log tool result event for session #{state.session_id}, tool #{tool_result_map[:name]}: #{inspect(reason)}"
        )

        :error
    end
  end

  @spec log_agent_step_event(State.t(), String.t(), map(), any(), any(), :ok | :error) ::
          :ok | :error
  defp log_agent_step_event(
         state,
         invocation_id,
         step_config,
         input,
         output_or_error,
         status \\ :ok
       ) do
    content = %{
      step_type: Map.get(step_config, :type),
      # Avoid storing the actual function
      step_details: Map.drop(step_config, [:type]),
      input: input,
      status: status,
      output: if(status == :ok, do: output_or_error, else: nil),
      error: if(status == :error, do: output_or_error, else: nil)
    }

    event_opts = [
      author: :agent,
      session_id: state.session_id,
      invocation_id: invocation_id,
      content: content
    ]

    case Memory.add_message(:in_memory, state.session_id, event_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to log agent step event for session #{state.session_id}, step #{inspect(step_config)}: #{inspect(reason)}"
        )

        :error
    end
  end

  # --- Start Link ---

  def start_link({config_map, opts}) when is_map(config_map) and is_list(opts) do
    GenServer.start_link(__MODULE__, config_map, opts)
  end

  def start_link(config_map) when is_map(config_map) do
    GenServer.start_link(__MODULE__, config_map, [])
  end
end
