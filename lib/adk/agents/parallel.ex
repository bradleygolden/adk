defmodule Adk.Agents.Parallel do
  @moduledoc """
  A parallel agent that executes multiple steps concurrently.

  This agent type is useful for running independent tasks that don't rely
  on each other's outputs, providing potential performance benefits.
  """
  use GenServer
  @behaviour Adk.Agent
  
  @impl Adk.Agent
  def run(agent, input), do: Adk.Agent.run(agent, input)

  @impl GenServer
  def init(config) do
    # Validate required config
    case validate_config(config) do
      :ok ->
        # Initialize state
        state = %{
          name: Map.get(config, :name),
          tasks: Map.get(config, :tasks, []),
          tools: Map.get(config, :tools, []),
          memory: %{},
          config: config
        }

        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl GenServer
  def handle_call({:run, input}, _from, state) do
    # Process the input for all tasks in parallel
    case run_parallel_tasks(input, state) do
      {:ok, outputs, new_state} ->
        # Combine the outputs into a single result
        result = %{
          output: outputs,
          combined: combine_outputs(outputs)
        }

        {:reply, {:ok, result}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  # Private functions

  defp validate_config(config) do
    cond do
      !is_map(config) ->
        {:error, "Config must be a map"}

      !is_list(Map.get(config, :tasks, [])) ->
        {:error, "Tasks must be a list"}

      true ->
        :ok
    end
  end

  defp run_parallel_tasks(input, state) do
    # Store the input in memory
    initial_state = Map.put(state, :memory, Map.put(state.memory, :input, input))

    # Execute all tasks in parallel using Task.async_stream
    task_results =
      state.tasks
      |> Enum.with_index()
      |> Task.async_stream(
        fn {task, index} ->
          {index, execute_task(task, input, initial_state)}
        end,
        ordered: true
      )
      |> Enum.reduce(%{}, fn {:ok, {index, result}}, acc ->
        Map.put(acc, index, result)
      end)

    # Check if any tasks failed
    error_results =
      task_results
      |> Enum.filter(fn {_index, {status, _, _}} -> status == :error end)

    if Enum.empty?(error_results) do
      # All tasks succeeded, collect outputs
      outputs =
        task_results
        |> Enum.map(fn {index, {_status, output, _}} ->
          {index, output}
        end)
        |> Enum.into(%{})

      # Merge all task states
      final_memory =
        task_results
        |> Enum.reduce(initial_state.memory, fn {_index, {_status, _output, task_state}}, acc ->
          Map.merge(acc, task_state.memory)
        end)

      final_state = Map.put(initial_state, :memory, final_memory)

      {:ok, outputs, final_state}
    else
      # At least one task failed
      {_index, {_status, reason, new_state}} = List.first(error_results)
      {:error, reason, new_state}
    end
  end

  defp execute_task(%{type: "tool", tool: tool_name, params: params}, _input, state) do
    # Execute a tool
    case Adk.Tool.execute(String.to_atom(tool_name), params) do
      {:ok, result} ->
        # Store the result in memory
        new_memory = Map.put(state.memory, tool_name, result)
        new_state = Map.put(state, :memory, new_memory)
        {:ok, result, new_state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp execute_task(%{type: "function", function: function}, input, state)
       when is_function(function, 1) do
    # Execute a function
    try do
      result = function.(input)
      {:ok, result, state}
    rescue
      e ->
        {:error, "Function execution failed: #{inspect(e)}", state}
    end
  end

  defp execute_task(%{type: "transform", transform: transform_fn}, input, state)
       when is_function(transform_fn, 2) do
    # Execute a transform function with access to state
    try do
      result = transform_fn.(input, state.memory)
      {:ok, result, state}
    rescue
      e ->
        {:error, "Transform execution failed: #{inspect(e)}", state}
    end
  end

  defp execute_task(unknown_task, _input, state) do
    {:error, "Unknown task type: #{inspect(unknown_task)}", state}
  end

  defp combine_outputs(outputs) when is_map(outputs) do
    # Combine all outputs into a string
    outputs
    |> Enum.sort_by(fn {index, _} -> index end)
    |> Enum.map_join("\n", fn {_index, output} ->
      if is_binary(output), do: output, else: inspect(output)
    end)
  end

  def start_link({config, opts}) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  def start_link(config) when is_map(config) do
    GenServer.start_link(__MODULE__, config, [])
  end
end
