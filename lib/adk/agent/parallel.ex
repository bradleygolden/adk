defmodule Adk.Agent.Parallel do
  @moduledoc """
  Implements a parallel workflow agent per the Adk pattern.

  This agent executes multiple tasks concurrently (tools, functions, or transforms),
  collecting their outputs. Tasks are defined in the agent's configuration.
  Implements the `Adk.Agent` behaviour.

  The `run/2` function returns a map with:
  - `:output`: A map where keys are 0-based indices of the tasks and values are their results.
  - `:combined`: An aggregated result (e.g., a list or string of individual outputs).

  See https://google.github.io/adk-docs/Agent/Workflow-agents for design rationale.
  """
  alias Adk.Memory
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
      # List of task maps (similar to steps in Sequential)
      :tasks,
      # Optional: List of tool names relevant to this agent
      tools: [],
      # Optional: Session ID for context, managed externally
      session_id: nil,
      # Optional: Invocation ID for context, managed externally
      invocation_id: nil,
      # Optional: Timeout for each parallel task in milliseconds
      task_timeout: 30_000,
      # Optional: Should the run return immediately on the first task error?
      halt_on_error: true
    ]
  end

  # --- Public API ---

  @doc """
  Creates a new Parallel agent config struct after validation.
  """
  def new(config_map) when is_map(config_map) do
    validate_and_build_config(config_map)
  end

  @doc """
  Executes the parallel workflow defined by the agent configuration struct.

  It relies on `session_id` and `invocation_id` being potentially set
  in the `%Config{}` struct by the caller (e.g., `Adk.Agent.Server`)
  for logging and context.
  """
  @impl Adk.Agent
  def run(%Config{} = config, input) do
    session_id = config.session_id || "stateless-session-#{UUID.uuid4()}"
    invocation_id = config.invocation_id || "stateless-invocation-#{UUID.uuid4()}"

    log_event(:user, input, config, session_id, invocation_id)

    # Execute all tasks concurrently using Task.async_stream
    task_stream =
      config.tasks
      |> Enum.with_index()
      |> Task.async_stream(
        fn {task, index} ->
          # Pass necessary context
          {index, execute_task(task, input, config, session_id, invocation_id)}
        end,
        # Process results as they complete
        ordered: false,
        # Limit concurrency reasonably
        max_concurrency: System.schedulers_online() * 2,
        timeout: config.task_timeout,
        on_timeout: :kill_task
      )

    # Collect results, separating successes and failures
    # {success_map, failure_list}
    initial_acc = {%{}, []}

    {successes, failures} =
      Enum.reduce_while(task_stream, initial_acc, fn
        {:ok, {index, {:ok, output}}}, {succ_acc, fail_acc} ->
          {:cont, {Map.put(succ_acc, index, output), fail_acc}}

        {:ok, {index, {:error, reason}}}, {succ_acc, fail_acc} ->
          failure_info = {index, reason}
          # Halt if configured to do so, otherwise continue collecting
          if config.halt_on_error do
            {:halt, {succ_acc, [failure_info | fail_acc]}}
          else
            {:cont, {succ_acc, [failure_info | fail_acc]}}
          end

        # Handle task timeout explicitly
        {:exit, {:timeout, _details}}, {succ_acc, fail_acc} ->
          failure_info = {:timeout, :task_timeout}

          Logger.error(
            "[#{session_id}/#{invocation_id}] Parallel task timed out after #{config.task_timeout}ms."
          )

          if config.halt_on_error do
            {:halt, {succ_acc, [failure_info | fail_acc]}}
          else
            {:cont, {succ_acc, [failure_info | fail_acc]}}
          end

        # Handle other task exits
        {:exit, reason}, {succ_acc, fail_acc} ->
          failure_info = {:stream_exit, reason}

          Logger.error(
            "[#{session_id}/#{invocation_id}] Parallel task exited unexpectedly: #{inspect(reason)}"
          )

          if config.halt_on_error do
            {:halt, {succ_acc, [failure_info | fail_acc]}}
          else
            {:cont, {succ_acc, [failure_info | fail_acc]}}
          end
      end)
      # If reduce_while finished normally (not halted), the acc is returned directly.
      # If halted, the halt value (acc) is returned.
      |> case do
        # Covers both normal finish and halt
        {s, f} -> {s, f}
      end

    # Process final results
    if Enum.empty?(failures) do
      # All tasks succeeded
      combined_output = combine_outputs(successes)
      result = %{output: successes, combined: combined_output}
      log_event(:agent, combined_output, config, session_id, invocation_id)
      {:ok, result}
    else
      # Some tasks failed
      first_failure_reason = List.first(failures)

      error =
        {:parallel_task_failed, first_failure_reason, %{successes: successes, failures: failures}}

      log_event(:error, error, config, session_id, invocation_id)
      {:error, error}
    end
  end

  # --- Private Functions ---

  # Config Validation
  defp validate_and_build_config(config_map) do
    required_keys = [:name, :tasks]
    missing_keys = Enum.filter(required_keys, &(!Map.has_key?(config_map, &1)))

    if !Enum.empty?(missing_keys) do
      {:error, {:invalid_config, :missing_keys, missing_keys}}
    else
      try do
        # Set defaults for optional fields
        defaults = %{tools: [], task_timeout: 30_000, halt_on_error: true}
        config = struct!(Config, Map.merge(defaults, config_map))

        with :ok <- validate_tasks(config.tasks),
             :ok <- validate_timeout(config.task_timeout) do
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

  defp validate_tasks(tasks) when not is_list(tasks) do
    {:error, {:invalid_config, :tasks_not_a_list, tasks}}
  end

  defp validate_tasks(tasks) do
    # Basic validation: Ensure each task is a map with a 'type'
    Enum.reduce_while(tasks, :ok, fn task, :ok ->
      if is_map(task) and Map.has_key?(task, :type) do
        {:cont, :ok}
      else
        {:halt, {:error, {:invalid_config, :invalid_task_format, task}}}
      end
    end)
    |> case do
      :ok -> :ok
      # Propagate the halt value
      {:error, reason} -> reason
    end
  end

  defp validate_timeout(timeout) when not is_integer(timeout) or timeout <= 0 do
    {:error, {:invalid_config, :invalid_task_timeout, timeout}}
  end

  defp validate_timeout(_timeout), do: :ok

  # Execute a single task (similar structure to execute_step in Sequential)
  defp execute_task(
         %{type: "tool", tool: tool_name_str, params: params} = _task_config,
         # Tool tasks often ignore direct input
         _input,
         # Config passed but maybe not needed here directly
         %Config{} = _config,
         session_id,
         invocation_id
       ) do
    tool_name = tool_name_str

    context = %{
      session_id: session_id,
      invocation_id: invocation_id,
      # Parallel agent doesn't generate tool_call_ids
      tool_call_id: nil
    }

    case ToolRegistry.execute_tool(tool_name, params, context) do
      {:ok, result} ->
        _tool_result_map = %{tool_call_id: nil, name: tool_name, content: result, status: :ok}
        # Logging from within async tasks can be tricky, especially with memory.
        # Consider logging task results *after* the stream is collected if needed.
        # For now, we skip detailed logging from within the task itself.
        # log_tool_result_event(config, session_id, invocation_id, tool_result_map)
        {:ok, result}

      {:error, reason} ->
        error_content = "Error executing tool '#{tool_name}': #{inspect(reason)}"

        _tool_result_map = %{
          tool_call_id: nil,
          name: tool_name,
          content: error_content,
          status: :error
        }

        # log_tool_result_event(config, session_id, invocation_id, tool_result_map)
        {:error, {:task_execution_error, :tool, tool_name, reason}}
    end
  end

  defp execute_task(
         %{type: "function", function: function} = _task_config,
         input,
         %Config{} = _config,
         # Not directly used for logging inside task for now
         _session_id,
         _invocation_id
       )
       when is_function(function, 1) do
    try do
      result = function.(input)
      # log_agent_task_event(config, session_id, invocation_id, task_config, input, result)
      {:ok, result}
    rescue
      e ->
        reason = {:task_execution_error, :function, inspect(function), e}

        # log_agent_task_event(config, session_id, invocation_id, task_config, input, reason, :error)
        {:error, reason}
    end
  end

  defp execute_task(
         %{type: "transform", transform: transform_fn} = _task_config,
         input,
         %Config{} = _config,
         session_id,
         _invocation_id
       )
       when is_function(transform_fn, 2) do
    # Memory access *might* be safe depending on the memory adapter, but could cause contention.
    # Fetching memory state for *each* parallel task might be inefficient.
    # Consider if the transform truly needs up-to-the-millisecond state or
    # if state fetched once before the parallel run is sufficient.
    case Memory.get_full_state(:in_memory, session_id) do
      {:ok, memory_state} ->
        try do
          result = transform_fn.(input, memory_state)
          # log_agent_task_event(config, session_id, invocation_id, task_config, input, result)
          {:ok, result}
        rescue
          e ->
            reason = {:task_execution_error, :transform, inspect(transform_fn), e}

            # log_agent_task_event(config, session_id, invocation_id, task_config, input, reason, :error)
            {:error, reason}
        end

      {:error, reason} ->
        mem_reason = {:memory_error, :get_full_state_failed, reason}

        # log_agent_task_event(config, session_id, invocation_id, task_config, input, mem_reason, :error)
        {:error, mem_reason}
    end
  end

  defp execute_task(unknown_task, _input, %Config{} = _config, session_id, invocation_id) do
    Logger.error(
      "[#{session_id}/#{invocation_id}] Unknown task type encountered in Parallel Agent: #{inspect(unknown_task)}"
    )

    reason = {:task_execution_error, :unknown_type, unknown_task}
    # log_agent_task_event(config, session_id, invocation_id, unknown_task, input, reason, :error)
    {:error, reason}
  end

  # --- Helper Functions ---

  # Combine outputs - example: concatenate strings or join lists
  # Customize this based on expected output types
  defp combine_outputs(success_map) do
    success_map
    |> Map.values()
    |> Enum.map_join("\n", fn
      output when is_binary(output) -> output
      output -> inspect(output)
    end)
  end

  # Logging functions (now called from the main run/2)
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

  # NOTE: Logging individual task/tool results from within async tasks is deferred
  # to avoid potential issues with concurrent memory access or log flooding.
  # The main :user input, final :agent output/:error are logged.

  # defp log_tool_result_event(_config, session_id, invocation_id, tool_result_map) do ... end
  # defp log_agent_task_event(_config, session_id, invocation_id, task_config, input, output_or_error, status \\ :ok) do ... end
end
