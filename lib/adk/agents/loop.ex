defmodule Adk.Agents.Loop do
  @moduledoc """
  Implements a loop workflow agent per the Adk pattern.

  This agent executes a series of steps repeatedly until a condition is met or a maximum number of iterations is reached. Steps and the loop condition are defined in the agent's configuration. Supports logging, memory integration, and error propagation. Implements the `Adk.Agent` behaviour.

  Extension points:
  - Add new step types by extending `execute_step/5`.
  - Customize event logging by overriding helper functions.
  - See https://google.github.io/adk-docs/Agents/Workflow-agents for design rationale.
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
  def run(agent, input), do: Adk.Agent.run(agent, input)

  @impl Adk.Agent
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

    # Log initial input as an event
    user_event_opts = [
      author: :user,
      content: input,
      session_id: state.session_id,
      invocation_id: invocation_id
    ]

    case Memory.add_message(:in_memory, state.session_id, user_event_opts) do
      :ok ->
        # Start the loop execution
        case run_loop(input, state, invocation_id) do
          # run_loop now returns {:ok, output} | {:error, reason} | {:max_iterations_reached, output}
          {:ok, output} ->
            {:reply, {:ok, %{output: output, status: :condition_met}}, state}

          {:max_iterations_reached, output} ->
            {:reply, {:ok, %{output: output, status: :max_iterations_reached}}, state}

          {:error, reason} ->
            # Reason should be a descriptive tuple
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        error_tuple = {:error, {:memory_error, :add_message_failed, {:user_input, reason}}}
        {:reply, error_tuple, state}
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

  # Loop Execution Logic
  defp run_loop(initial_input, %State{} = state, invocation_id) do
    iterate(initial_input, 0, state, invocation_id)
  end

  # Recursive Iteration Function
  defp iterate(current_output, current_iteration, %State{} = state, invocation_id) do
    # Log start of iteration
    log_agent_loop_event(state, invocation_id, :iteration_start, %{
      iteration: current_iteration,
      input: current_output
    })

    # Check max iterations
    if current_iteration >= state.config.max_iterations do
      Logger.info(
        "Loop agent #{state.config.name} (session #{state.session_id}) reached max iterations (#{state.config.max_iterations})."
      )

      log_agent_loop_event(state, invocation_id, :max_iterations_reached, %{
        iteration: current_iteration,
        output: current_output
      })

      {:max_iterations_reached, current_output}
    else
      # Check condition
      check_condition_and_proceed(current_output, current_iteration, state, invocation_id)
    end
  end

  # Helper to check condition and continue iteration
  defp check_condition_and_proceed(
         current_output,
         current_iteration,
         %State{} = state,
         invocation_id
       ) do
    # Fetch current memory state for condition check
    case Memory.get_full_state(:in_memory, state.session_id) do
      {:ok, memory_state} ->
        condition_fn = state.config.condition

        try do
          condition_result = condition_fn.(current_output, memory_state)

          log_agent_loop_event(state, invocation_id, :condition_check, %{
            iteration: current_iteration,
            output: current_output,
            # Avoid logging full state
            memory_state_keys: Map.keys(memory_state),
            condition_result: condition_result
          })

          case condition_result do
            true ->
              # Condition met, loop finishes successfully
              log_agent_loop_event(state, invocation_id, :condition_met, %{
                iteration: current_iteration,
                final_output: current_output
              })

              {:ok, current_output}

            false ->
              # Condition not met, run steps and iterate again
              run_steps_and_iterate(current_output, current_iteration, state, invocation_id)
          end
        rescue
          e ->
            reason = {:condition_error, e, __STACKTRACE__}

            log_agent_loop_event(state, invocation_id, :condition_error, %{
              iteration: current_iteration,
              error: reason
            })

            {:error, reason}
        end

      {:error, reason} ->
        mem_reason = {:memory_error, :get_full_state_failed, reason}

        log_agent_loop_event(state, invocation_id, :memory_error, %{
          iteration: current_iteration,
          operation: :get_full_state,
          error: reason
        })

        {:error, mem_reason}
    end
  end

  # Helper to run steps for one iteration and recurse
  defp run_steps_and_iterate(current_output, current_iteration, %State{} = state, invocation_id) do
    case run_steps_for_iteration(current_output, state, invocation_id, current_iteration) do
      {:ok, new_output} ->
        # Recurse for the next iteration
        iterate(new_output, current_iteration + 1, state, invocation_id)

      {:error, reason} ->
        # Propagate error from step execution
        # Error was already logged within run_steps_for_iteration/execute_step
        {:error, reason}
    end
  end

  # Run all steps for a single iteration
  defp run_steps_for_iteration(input, %State{} = state, invocation_id, current_iteration) do
    # Accumulator holds {:ok | :error, latest_output}
    initial_acc = {:ok, input}

    Enum.reduce_while(state.config.steps, initial_acc, fn step, {:ok, acc_output} ->
      case execute_step(step, acc_output, state, invocation_id, current_iteration) do
        {:ok, step_output} ->
          # Continue with the new output for the next step in this iteration
          {:cont, {:ok, step_output}}

        {:error, reason} ->
          # Halt this iteration's steps on error
          {:halt, {:error, reason}}
      end
    end)

    # Return final output of iteration or the error that halted it
  end

  # Execute a single step (similar to Sequential Agent, but uses Loop's State)
  defp execute_step(
         %{type: "tool", tool: tool_name_str, params: params} = _step_config,
         # Tool steps often ignore direct input
         _input,
         %State{} = state,
         invocation_id,
         # Iteration number not needed for tool context
         _current_iteration
       ) do
    # Keep as string for ToolRegistry
    tool_name = tool_name_str

    context = %{
      session_id: state.session_id,
      invocation_id: invocation_id,
      # Loop agent doesn't generate tool_call_ids
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
         invocation_id,
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

  defp execute_step(
         %{type: "transform", transform: transform_fn} = step_config,
         input,
         %State{} = state,
         invocation_id,
         current_iteration
       )
       when is_function(transform_fn, 2) do
    case Memory.get_full_state(:in_memory, state.session_id) do
      {:ok, memory_state} ->
        try do
          result = transform_fn.(input, memory_state)

          log_agent_step_event(
            state,
            invocation_id,
            current_iteration,
            step_config,
            input,
            result
          )

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

      {:error, reason} ->
        mem_reason = {:memory_error, :get_full_state_failed, reason}

        log_agent_step_event(
          state,
          invocation_id,
          current_iteration,
          step_config,
          input,
          mem_reason,
          :error
        )

        {:error, mem_reason}
    end
  end

  defp execute_step(unknown_step, input, %State{} = state, invocation_id, current_iteration) do
    Logger.error(
      "Unknown step type encountered in Loop Agent #{state.config.name}: #{inspect(unknown_step)}"
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

  # --- Helper Functions for Logging Events ---

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

  defp log_agent_step_event(
         state,
         invocation_id,
         current_iteration,
         step_config,
         input,
         output_or_error,
         status \\ :ok
       ) do
    content = %{
      iteration: current_iteration,
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
      # Store step details in content
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

  defp log_agent_loop_event(state, invocation_id, event_type, details) do
    content = Map.merge(%{event: event_type}, details)

    event_opts = [
      author: :agent,
      session_id: state.session_id,
      invocation_id: invocation_id,
      # Store loop details in content
      content: content
    ]

    case Memory.add_message(:in_memory, state.session_id, event_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to log agent loop event for session #{state.session_id}, type #{event_type}: #{inspect(reason)}"
        )

        :error
    end
  end

  # --- Start Link ---

  def start_link(config_map, opts \\ []) when is_map(config_map) do
    GenServer.start_link(__MODULE__, config_map, opts)
  end
end
