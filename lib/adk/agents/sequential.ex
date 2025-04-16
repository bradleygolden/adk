defmodule Adk.Agents.Sequential do
  @moduledoc """
  A sequential agent that executes a series of steps in order.
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
          steps: Map.get(config, :steps, []),
          tools: Map.get(config, :tools, []),
          current_step: 0,
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
    # Process the input through each step
    case run_steps(input, state) do
      {:ok, output, new_state} ->
        {:reply, {:ok, output}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  # Private functions

  defp validate_config(config) do
    cond do
      !is_map(config) ->
        {:error, "Config must be a map"}

      true ->
        :ok
    end
  end

  defp run_steps(input, state) do
    # Start with the input as the initial value
    initial_state = Map.put(state, :memory, Map.put(state.memory, :input, input))

    # Run each step in sequence, passing the output of each step to the next
    Enum.reduce_while(state.steps, {:ok, %{output: input}, initial_state}, fn step,
                                                                              {:ok, acc,
                                                                               current_state} ->
      case execute_step(step, acc.output, current_state) do
        {:ok, step_output, new_state} ->
          # Continue to the next step
          {:cont, {:ok, %{output: step_output}, new_state}}

        {:error, reason, new_state} ->
          # Stop processing and return the error
          {:halt, {:error, reason, new_state}}
      end
    end)
  end

  defp execute_step(%{type: "tool", tool: tool_name, params: params}, _input, state) do
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

  defp execute_step(%{type: "function", function: function}, input, state)
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

  defp execute_step(%{type: "transform", transform: transform_fn}, input, state)
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

  defp execute_step(unknown_step, _input, state) do
    {:error, "Unknown step type: #{inspect(unknown_step)}", state}
  end

  def start_link({config, opts}) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  def start_link(config) when is_map(config) do
    GenServer.start_link(__MODULE__, config, [])
  end
end
