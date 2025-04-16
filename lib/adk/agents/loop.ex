defmodule Adk.Agents.Loop do
  @moduledoc """
  A loop agent that executes steps repeatedly until a condition is met.

  This agent type is useful for iterative tasks or processing that needs
  to continue until some criterion is satisfied.
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
          condition: Map.get(config, :condition),
          max_iterations: Map.get(config, :max_iterations, 10),
          tools: Map.get(config, :tools, []),
          current_iteration: 0,
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
    # Process the input through the loop
    case run_loop(input, state) do
      {:ok, output, new_state} ->
        {:reply, {:ok, %{output: output, iterations: new_state.current_iteration}}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  # Private functions

  defp validate_config(config) do
    cond do
      !is_map(config) ->
        {:error, "Config must be a map"}

      !is_function(Map.get(config, :condition), 2) ->
        {:error, "A condition function must be provided"}

      !is_list(Map.get(config, :steps, [])) ->
        {:error, "Steps must be a list"}

      true ->
        :ok
    end
  end

  defp run_loop(input, state) do
    # Store the input in memory
    initial_state = %{
      state
      | memory: Map.put(state.memory, :input, input),
        current_iteration: 0
    }

    loop_result = iterate(input, initial_state)

    case loop_result do
      {:ok, final_output, final_state} ->
        {:ok, final_output, final_state}

      {:error, reason, final_state} ->
        {:error, reason, final_state}

      {:max_iterations_reached, last_output, final_state} ->
        # Reached max iterations, but this is not an error
        {:ok, last_output, final_state}
    end
  end

  defp iterate(current_output, state) do
    # Check if we've reached max iterations
    if state.current_iteration >= state.max_iterations do
      {:max_iterations_reached, current_output, state}
    else
      # Check if the condition is met
      condition_fn = state.condition

      case condition_fn.(current_output, state.memory) do
        true ->
          # Condition is met, exit the loop
          {:ok, current_output, state}

        false ->
          # Execute one iteration of steps
          case run_steps(current_output, state) do
            {:ok, new_output, new_state} ->
              # Increment iteration counter
              next_state = %{new_state | current_iteration: new_state.current_iteration + 1}

              # Update memory with the iteration result
              updated_memory =
                Map.put(
                  next_state.memory,
                  :"iteration_#{next_state.current_iteration}",
                  new_output
                )

              next_state = %{next_state | memory: updated_memory}

              # Continue to the next iteration
              iterate(new_output, next_state)

            {:error, reason, new_state} ->
              # Propagate the error
              {:error, reason, new_state}
          end
      end
    end
  end

  defp run_steps(input, state) do
    # Start with the input as the initial value
    # Run each step in sequence, passing the output of each step to the next
    Enum.reduce_while(state.steps, {:ok, input, state}, fn step, {:ok, acc, current_state} ->
      case execute_step(step, acc, current_state) do
        {:ok, step_output, new_state} ->
          # Continue to the next step
          {:cont, {:ok, step_output, new_state}}

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
