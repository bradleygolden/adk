defmodule Adk.Agents.Parallel do
  @moduledoc """
  Implements a parallel workflow agent per the Adk pattern.

  This agent executes multiple tasks concurrently (tools, functions, or transforms), collecting their outputs. Tasks are defined in the agent's configuration. Supports logging, memory integration, and error propagation. Implements the `Adk.Agent` behaviour.

  Extension points:
  - Add new task types by extending `execute_task/4`.
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
    Configuration struct for the Parallel Agent.
    """
    @enforce_keys [:name, :tasks]
    defstruct [
      :name,
      # List of task maps (similar to steps in Sequential/Loop)
      :tasks,
      # Optional: List of tool names relevant to this agent
      tools: []
    ]
  end

  defmodule State do
    @moduledoc """
    Internal state struct for the Parallel Agent GenServer.
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
        # Process the input for all tasks in parallel
        case run_parallel_tasks(input, state, invocation_id) do
          {:ok, outputs} ->
            # Combine the outputs into the final result structure
            result = %{
              # Map of index -> individual output
              output: outputs,
              combined: combine_outputs(outputs)
            }

            # State doesn't change during run
            {:reply, {:ok, result}, state}

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

  @impl GenServer
  def handle_call(:get_state, _from, %State{} = state) do
    {:reply, {:ok, state}, state}
  end

  # --- Private Functions ---

  # Config Validation
  defp validate_and_build_config(config_map) do
    # 1. Check for required keys first
    required_keys = [:name, :tasks]
    missing_keys = Enum.filter(required_keys, &(!Map.has_key?(config_map, &1)))

    if !Enum.empty?(missing_keys) do
      {:error, {:invalid_config, :missing_keys, missing_keys}}
    else
      # 2. Attempt struct conversion (should succeed for required keys now)
      try do
        # No defaults to set here, unlike LLM agent
        config = struct!(Config, config_map)

        # 3. Perform further validations
        with :ok <- validate_tasks(config.tasks) do
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

  defp validate_tasks(tasks) when not is_list(tasks) do
    {:error, {:invalid_config, :tasks_not_a_list, tasks}}
  end

  # Basic list check for now
  defp validate_tasks(_tasks), do: :ok

  # Parallel Task Execution
  defp run_parallel_tasks(input, %State{} = state, invocation_id) do
    # Execute all tasks concurrently using Task.async_stream
    # The stream yields {:ok, {index, task_result}} or {:exit, reason}
    # task_result is {:ok, output} | {:error, reason} from execute_task
    task_stream =
      state.config.tasks
      |> Enum.with_index()
      |> Task.async_stream(
        fn {task, index} ->
          # Pass the original state and invocation_id to each task execution
          {index, execute_task(task, input, state, invocation_id)}
        end,
        ordered: false,
        # Example timeout
        timeout: 30_000
      )

    # Collect results, separating successes and failures
    {successes, failures} =
      Enum.reduce(task_stream, {%{}, []}, fn
        # Task completed successfully
        {:ok, {index, {:ok, output}}}, {succ_acc, fail_acc} ->
          {Map.put(succ_acc, index, output), fail_acc}

        # Task returned an error
        {:ok, {index, {:error, reason}}}, {succ_acc, fail_acc} ->
          {succ_acc, [{index, reason} | fail_acc]}

        # Task exited unexpectedly
        {:exit, reason}, {succ_acc, fail_acc} ->
          Logger.error("Parallel task exited unexpectedly: #{inspect(reason)}")
          {succ_acc, [{:stream_exit, reason} | fail_acc]}
      end)

    # Check if any tasks failed
    if Enum.empty?(failures) do
      # All tasks succeeded
      {:ok, successes}
    else
      # At least one task failed, return the first failure encountered
      first_failure_reason = List.first(failures)
      {:error, {:parallel_task_failed, first_failure_reason}}
    end
  end

  # Execute a single task (similar structure to execute_step in other agents)
  defp execute_task(
         %{type: "tool", tool: tool_name_str, params: params} = _task_config,
         # Tool tasks often ignore direct input
         _input,
         %State{} = state,
         invocation_id
       ) do
    # Keep as string for ToolRegistry
    tool_name = tool_name_str

    context = %{
      session_id: state.session_id,
      invocation_id: invocation_id,
      # Parallel agent doesn't generate tool_call_ids
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
        {:error, {:task_execution_error, :tool, tool_name, reason}}
    end
  end

  defp execute_task(
         %{type: "function", function: function} = task_config,
         input,
         %State{} = state,
         invocation_id
       )
       when is_function(function, 1) do
    try do
      result = function.(input)
      log_agent_task_event(state, invocation_id, task_config, input, result)
      {:ok, result}
    rescue
      e ->
        reason = {:task_execution_error, :function, inspect(function), e}
        log_agent_task_event(state, invocation_id, task_config, input, reason, :error)
        {:error, reason}
    end
  end

  defp execute_task(
         %{type: "transform", transform: transform_fn} = task_config,
         input,
         %State{} = state,
         invocation_id
       )
       when is_function(transform_fn, 2) do
    # Fetch memory state *once* before the transform.
    # Note: This state might not reflect updates from other concurrent tasks.
    case Memory.get_full_state(:in_memory, state.session_id) do
      {:ok, memory_state} ->
        try do
          result = transform_fn.(input, memory_state)
          log_agent_task_event(state, invocation_id, task_config, input, result)
          {:ok, result}
        rescue
          e ->
            reason = {:task_execution_error, :transform, inspect(transform_fn), e}
            log_agent_task_event(state, invocation_id, task_config, input, reason, :error)
            {:error, reason}
        end

      {:error, reason} ->
        mem_reason = {:memory_error, :get_full_state_failed, reason}
        log_agent_task_event(state, invocation_id, task_config, input, mem_reason, :error)
        {:error, mem_reason}
    end
  end

  defp execute_task(unknown_task, input, %State{} = state, invocation_id) do
    Logger.error(
      "Unknown task type encountered in Parallel Agent #{state.config.name}: #{inspect(unknown_task)}"
    )

    reason = {:task_execution_error, :unknown_type, unknown_task}
    log_agent_task_event(state, invocation_id, unknown_task, input, reason, :error)
    {:error, reason}
  end

  # Helper to combine outputs into a single string
  defp combine_outputs(outputs) when is_map(outputs) do
    outputs
    # Sort by original task index
    |> Enum.sort_by(fn {index, _} -> index end)
    |> Enum.map_join("\n", fn {_index, output} ->
      # Convert non-binary outputs to string representation
      if is_binary(output), do: output, else: inspect(output)
    end)
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

  defp log_agent_task_event(
         state,
         invocation_id,
         task_config,
         input,
         output_or_error,
         status \\ :ok
       ) do
    content = %{
      task_type: Map.get(task_config, :type),
      # Avoid storing the actual function
      task_details: Map.drop(task_config, [:type]),
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
          "Failed to log agent task event for session #{state.session_id}, task #{inspect(task_config)}: #{inspect(reason)}"
        )

        :error
    end
  end

  # --- Start Link ---

  def start_link(config_map, opts \\ []) when is_map(config_map) do
    GenServer.start_link(__MODULE__, config_map, opts)
  end
end
