defmodule Adk.Agent.Loop do
  @moduledoc """
  Implements a loop workflow agent per the Adk pattern.

  This agent executes a series of steps repeatedly until a condition is met or a maximum number of iterations is reached. Steps and the loop condition are defined in the agent's configuration. Supports logging, memory integration, and error propagation. Implements the `Adk.Agent` behaviour.

  Extension points:
  - Add new step types by extending `execute_step/5`.
  - Customize event logging by overriding helper functions.
  - See https://google.github.io/adk-docs/Agent/Workflow-agents for design rationale.
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
    Configuration struct for the Loop Agent.
    """
    @enforce_keys [:name, :steps, :condition]
    defstruct [
      :name,
      # List of step maps
      :steps,
      # Function/2: (current_output, memory_state) -> boolean
      :condition,
      max_iterations: 10,
      # Optional: List of tool names relevant to this agent
      tools: []
    ]
  end

  defmodule State do
    @moduledoc """
    Internal state struct for the Loop Agent GenServer.
    """
    @enforce_keys [:session_id, :config]
    defstruct [
      :session_id,
      # Holds the %Config{} struct
      :config
    ]
  end

  # --- Agent API ---

  @impl Adk.Agent
  def run(%Config{} = config, initial_input) do
    # Create a temporary, stateless 'State' for execution context
    dummy_state = %State{session_id: "stateless", config: config}
    dummy_invocation_id = "stateless-invoke"

    # Start the iteration logic directly
    iterate_struct(initial_input, 0, dummy_state, dummy_invocation_id)
  end

  def handle_request(_input, state), do: {:ok, %{output: "Not implemented"}, state}

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
  def handle_call({:run, input}, _from, %State{} = state) do
    invocation_id = UUID.uuid4()

    # Log initial input
    log_event(:user, input, state, invocation_id)

    # Delegate core loop logic to struct-based run/2
    case run(state.config, input) do
      # run now returns {:ok, output_map} | {:error, reason}
      {:ok, output_map} ->
        # Log final output (regardless of status)
        log_event(:agent, output_map.output, state, invocation_id)
        {:reply, {:ok, output_map}, state}

      {:error, reason} ->
        # Log error
        log_event(:error, reason, state, invocation_id)
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_state, _from, %State{} = state) do
    {:reply, {:ok, state}, state}
  end

  # --- Private Functions ---

  # Config Validation
  defp validate_and_build_config(config_map) do
    # 1. Check for required keys first
    required_keys = [:name, :steps, :condition]
    missing_keys = Enum.filter(required_keys, &(!Map.has_key?(config_map, &1)))

    if !Enum.empty?(missing_keys) do
      {:error, {:invalid_config, :missing_keys, missing_keys}}
    else
      # 2. Set defaults if needed (max_iterations has a default in the struct def)
      # Ensure default is applied if key missing
      config_with_defaults = Map.put_new(config_map, :max_iterations, 10)

      # 3. Attempt struct conversion (should succeed for required keys now)
      try do
        config = struct!(Config, config_with_defaults)

        # 4. Perform further validations (already done implicitly by struct! for required, check others)
        with :ok <- validate_steps(config.steps),
             :ok <- validate_condition(config.condition),
             :ok <- validate_max_iterations(config.max_iterations) do
          {:ok, config}
        else
          # Capture the first validation error
          {:error, reason} -> {:error, reason}
        end
      rescue
        # Catch ArgumentError from struct! if types are wrong
        ArgumentError ->
          {:error, {:invalid_config, :struct_conversion_failed, config_with_defaults}}

        # Catch any other unexpected error during struct creation/validation
        e ->
          {:error, {:invalid_config, :unexpected_error, e}}
      end
    end
  end

  defp validate_steps(steps) when not is_list(steps) do
    {:error, {:invalid_config, :steps_not_a_list, steps}}
  end

  # Basic list check for now
  defp validate_steps(_steps), do: :ok

  defp validate_condition(cond) when not is_function(cond, 2) do
    {:error, {:invalid_config, :condition_not_function_arity_2, cond}}
  end

  defp validate_condition(_cond), do: :ok

  defp validate_max_iterations(iter) when not is_integer(iter) or iter < 0 do
    {:error, {:invalid_config, :max_iterations_invalid, iter}}
  end

  defp validate_max_iterations(_iter), do: :ok

  # --- NEW Struct-based Iteration Logic (replaces old iterate/check/run_steps) ---
  # Rename original iterate to avoid GenServer context dependency
  defp iterate_struct(current_output, current_iteration, %State{} = state, invocation_id) do
    # Log start of iteration (can use a simpler logger if memory isn't involved here)
    # Logger.debug("[Loop Agent Struct] Iteration #{current_iteration} starting...")

    # Check max iterations
    if current_iteration >= state.config.max_iterations do
      Logger.info(
        "[Loop Agent Struct] #{state.config.name} reached max iterations (#{state.config.max_iterations})."
      )

      # Log end event if needed
      {:ok, %{output: current_output, status: :max_iterations_reached}}
    else
      # Check condition
      # Note: Condition check for struct-based run CANNOT access live memory state easily.
      # If condition requires memory, the GenServer wrapper must be used,
      # or the condition logic adapted/passed differently.
      # Here, we assume condition only needs current_output or dummy memory state.
      condition_fn = state.config.condition
      dummy_memory_state = %{}

      try do
        # Pass dummy memory state to condition
        condition_result = condition_fn.(current_output, dummy_memory_state)
        # Log condition check if needed

        case condition_result do
          true ->
            # Condition met
            # Log end event if needed
            {:ok, %{output: current_output, status: :condition_met}}

          false ->
            # Condition not met, run steps
            case run_steps_struct(current_output, current_iteration, state, invocation_id) do
              {:ok, next_output} ->
                # Recurse
                iterate_struct(next_output, current_iteration + 1, state, invocation_id)

              {:error, reason} ->
                # Propagate step error
                {:error, reason}
            end
        end
      rescue
        e ->
          reason = {:condition_error, e, __STACKTRACE__}
          # Log error if needed
          {:error, reason}
      end
    end
  end

  # Helper to run steps for struct-based iteration
  defp run_steps_struct(input_for_steps, current_iteration, %State{} = state, invocation_id) do
    # Log step execution start if needed

    initial_acc = {:ok, input_for_steps}

    Enum.reduce_while(state.config.steps, initial_acc, fn step, {:ok, current_step_input} ->
      # Pass current_iteration to execute_step if needed, requires signature change
      # Assuming execute_step only needs state & invocation_id for context
      case execute_step(step, current_step_input, state, invocation_id, current_iteration) do
        {:ok, step_output} ->
          {:cont, {:ok, step_output}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)

    # No extra wrapping needed here, return {:ok, final_output} or {:error, reason}
  end

  # --- Original Step Execution Logic (Needs slight modification) ---
  # Add current_iteration parameter
  defp execute_step(
         %{type: "tool", tool: tool_name_str, params: params},
         _input,
         %State{} = state,
         invocation_id,
         # Added
         current_iteration
       ) do
    tool_name = tool_name_str

    context = %{
      session_id: state.session_id,
      invocation_id: invocation_id,
      tool_call_id: nil,
      # Add iteration context
      loop_iteration: current_iteration
    }

    # Rest remains similar, maybe log iteration in tool execution?
    # ... (original tool execution logic) ...
    case ToolRegistry.execute_tool(tool_name, params, context) do
      {:ok, result} ->
        log_tool_result_event(state, invocation_id, current_iteration, %{
          tool_call_id: nil,
          name: tool_name,
          content: result,
          status: :ok
        })

        {:ok, result}

      {:error, reason} ->
        log_tool_result_event(state, invocation_id, current_iteration, %{
          tool_call_id: nil,
          name: tool_name,
          content: inspect(reason),
          status: :error
        })

        {:error, {:step_execution_error, :tool, tool_name, reason}}
    end
  end

  # Add current_iteration parameter
  defp execute_step(
         %{type: "function", function: function} = step_config,
         input,
         %State{} = state,
         invocation_id,
         # Added
         current_iteration
       )
       when is_function(function, 1) do
    try do
      result = function.(input)
      log_agent_step_event(state, invocation_id, current_iteration, step_config, input, result)
      {:ok, result}
    rescue
      e ->
        reason = {:step_execution_error, :function, inspect(function), e}

        log_agent_step_event(
          state,
          invocation_id,
          current_iteration,
          step_config,
          input,
          reason,
          :error
        )

        {:error, reason}
    end
  end

  # Add current_iteration parameter
  defp execute_step(
         %{type: "transform", transform: transform_fn} = step_config,
         input,
         %State{} = state,
         invocation_id,
         # Added
         current_iteration
       )
       when is_function(transform_fn, 2) do
    # Note: Transform using memory state might be problematic in struct-based run
    # unless memory state is passed differently or handled by GenServer only.
    # Using dummy state here for struct run.
    dummy_memory_state = %{}

    try do
      result = transform_fn.(input, dummy_memory_state)
      log_agent_step_event(state, invocation_id, current_iteration, step_config, input, result)
      {:ok, result}
    rescue
      e ->
        reason = {:step_execution_error, :transform, inspect(transform_fn), e}

        log_agent_step_event(
          state,
          invocation_id,
          current_iteration,
          step_config,
          input,
          reason,
          :error
        )

        {:error, reason}
    end

    # Previous memory fetch logic removed for struct-based run
  end

  # Add current_iteration parameter
  defp execute_step(unknown_step, input, %State{} = state, invocation_id, current_iteration) do
    Logger.error(
      "[Loop Agent Struct] Unknown step type in iteration #{current_iteration}: #{inspect(unknown_step)}"
    )

    reason = {:step_execution_error, :unknown_type, unknown_step}

    log_agent_step_event(
      state,
      invocation_id,
      current_iteration,
      unknown_step,
      input,
      reason,
      :error
    )

    {:error, reason}
  end

  # --- Update Logging Helpers --- (add iteration)
  defp log_tool_result_event(state, invocation_id, iteration, tool_result_map) do
    _event_opts = [
      author: :tool,
      session_id: state.session_id,
      invocation_id: invocation_id,
      content: nil,
      tool_results: [tool_result_map],
      # Add iteration metadata
      metadata: %{iteration: iteration}
    ]

    # Log using appropriate memory service if needed (or just Logger for struct run)
    # Assuming memory logging is primarily for GenServer context
    # Memory.add_message(:in_memory, state.session_id, event_opts)
    Logger.debug("Tool Result (Iter #{iteration}): #{inspect(tool_result_map)}")
    :ok
  end

  defp log_agent_step_event(
         state,
         invocation_id,
         iteration,
         step_config,
         input,
         output_or_error,
         status \\ :ok
       ) do
    content = %{
      step_type: Map.get(step_config, :type),
      step_details: Map.drop(step_config, [:type]),
      input: input,
      status: status,
      output: if(status == :ok, do: output_or_error, else: nil),
      error: if(status == :error, do: output_or_error, else: nil)
    }

    _event_opts = [
      author: :agent,
      session_id: state.session_id,
      invocation_id: invocation_id,
      content: content,
      # Add iteration metadata
      metadata: %{iteration: iteration}
    ]

    # Log using appropriate memory service if needed (or just Logger for struct run)
    # Memory.add_message(:in_memory, state.session_id, event_opts)
    Logger.debug("Agent Step Event (Iter #{iteration}): #{inspect(content)}")
    :ok
  end

  # Add main log_event helper
  defp log_event(author, content, %State{} = state, invocation_id) do
    event_opts = [
      author: author,
      content: content,
      session_id: state.session_id,
      invocation_id: invocation_id
      # No iteration meta needed for top-level user/agent/error events
    ]

    Memory.add_message(:in_memory, state.session_id, event_opts)
  end

  # --- Start Link ---

  def start_link(config_map, opts \\ []) when is_map(config_map) do
    GenServer.start_link(__MODULE__, config_map, opts)
  end
end
