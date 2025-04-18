defmodule Adk.Callback do
  @compile false

  @moduledoc """
  Defines the callback system for the Adk framework.

  Callbacks allow you to inject behavior at specific points in the agent lifecycle.
  This provides a powerful way to extend agent functionality without modifying core logic.

  ## Types of Callbacks

  There are several callback types that can be registered:

  - `:before_run` - Executed before an agent processes input
  - `:after_run` - Executed after an agent has processed input and produced output
  - `:before_llm_call` - Executed before making a call to the LLM
  - `:after_llm_call` - Executed after receiving a response from the LLM
  - `:before_tool_call` - Executed before invoking a tool
  - `:after_tool_call` - Executed after a tool returns a result
  - `:on_error` - Executed when an error occurs during processing

  ## Usage

  You can register callbacks either globally or for a specific agent:

  ```elixir
  # Register a global callback for all agents
  Adk.Callback.register(:before_run, fn input, context ->
    Logger.info("Processing input: \#{inspect(input)}")
    {:cont, input}
  end)

  # Register a callback for a specific agent
  Adk.Callback.register(:after_run, fn output, context ->
    Logger.info("Agent \#{context.agent_name} produced: \#{inspect(output)}")
    {:cont, output}
  end, %{agent_name: "my_agent"})
  ```

  ## Callback Return Values

  Callbacks must return one of the following:

  - `{:cont, modified_value}` - Continue processing with the possibly modified value
  - `{:halt, value}` - Stop the callback chain and return this value as the result

  ## Lifecycle

  Callbacks are executed in the order they were registered. Multiple callbacks
  of the same type form a pipeline, with each one receiving the output of the previous.
  If any callback returns `{:halt, value}`, the chain is stopped and that value
  is used as the final result.
  """

  require Logger

  # Callback definition
  @type callback_type ::
          :before_run
          | :after_run
          | :before_llm_call
          | :after_llm_call
          | :before_tool_call
          | :after_tool_call
          | :on_error

  @type callback_return :: {:cont, any()} | {:halt, any()}
  @type callback_fn :: (any(), map() -> callback_return())
  @type callback_filter :: map()

  # For storing the callbacks
  @callback_registry_name :adk_callbacks

  @doc """
  Returns the name of the ETS table used for storing callbacks.
  Used primarily for testing.
  """
  def callback_registry_name, do: @callback_registry_name

  @doc """
  Initializes the callback registry if it doesn't exist.
  Called automatically by the application supervisor.
  """
  def init do
    case :ets.info(@callback_registry_name) do
      :undefined ->
        :ets.new(@callback_registry_name, [:named_table, :set, :public])
        Logger.debug("Initialized ADK callback registry")
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Registers a callback function to be executed at the specified callback point.

  ## Parameters

  - `type`: The callback type (e.g., `:before_run`, `:after_llm_call`)
  - `callback`: The function to be called, should accept (value, context) and return {:cont, value} or {:halt, value}
  - `filter`: Optional map of conditions that must match for the callback to be executed

  ## Examples

      Adk.Callback.register(:before_run, fn input, ctx ->
        {:cont, transformed_input}
      end)

      Adk.Callback.register(:after_run, fn output, ctx ->
        {:cont, output}
      end, %{agent_name: "my_agent"})
  """
  @spec register(callback_type(), callback_fn(), callback_filter()) :: :ok
  def register(type, callback, filter \\ %{}) when is_function(callback, 2) and is_map(filter) do
    ensure_initialized()

    # Generate a unique ID for this callback
    id = System.unique_integer([:positive, :monotonic])
    callback_entry = {id, callback, filter}

    # Store the callback in ETS
    case :ets.lookup(@callback_registry_name, type) do
      [] ->
        # First callback of this type
        :ets.insert(@callback_registry_name, {type, [callback_entry]})

      [{^type, existing_callbacks}] ->
        # Add to existing callbacks of this type
        :ets.insert(@callback_registry_name, {type, existing_callbacks ++ [callback_entry]})
    end

    :ok
  end

  @doc """
  Unregisters a callback by its ID.

  ## Parameters

  - `type`: The callback type
  - `callback_id`: The ID of the callback to remove

  ## Returns

  - `:ok` if the callback was successfully removed
  - `{:error, :not_found}` if the callback wasn't found
  """
  @spec unregister(callback_type(), integer()) :: :ok | {:error, :not_found}
  def unregister(type, callback_id) do
    ensure_initialized()

    case :ets.lookup(@callback_registry_name, type) do
      [] ->
        {:error, :not_found}

      [{^type, callbacks}] ->
        # Find and remove the callback with the given ID
        filtered_callbacks = Enum.reject(callbacks, fn {id, _, _} -> id == callback_id end)

        if length(filtered_callbacks) < length(callbacks) do
          :ets.insert(@callback_registry_name, {type, filtered_callbacks})
          :ok
        else
          {:error, :not_found}
        end
    end
  end

  @doc """
  Unregisters all callbacks of a specific type that match the given filter.

  ## Parameters

  - `type`: The callback type
  - `filter`: Map of conditions to match

  ## Returns

  - `{:ok, count}` with the number of callbacks removed
  """
  @spec unregister_by_filter(callback_type(), callback_filter()) :: {:ok, non_neg_integer()}
  def unregister_by_filter(type, filter) when is_map(filter) do
    ensure_initialized()

    case :ets.lookup(@callback_registry_name, type) do
      [] ->
        {:ok, 0}

      [{^type, callbacks}] ->
        # Keep only callbacks that don't match the filter
        {to_keep, _to_remove} =
          Enum.split_with(callbacks, fn {_, _, cb_filter} ->
            !matches_filter?(cb_filter, filter)
          end)

        :ets.insert(@callback_registry_name, {type, to_keep})
        {:ok, length(callbacks) - length(to_keep)}
    end
  end

  @doc """
  Executes all registered callbacks of the specified type that match the context.

  ## Parameters

  - `type`: The callback type to execute
  - `value`: The value to pass to the callbacks
  - `context`: The execution context, used for filtering

  ## Returns

  - `{:ok, value}` with the final value after all callbacks
  - `{:halt, value}` if a callback halted the chain
  """
  @spec execute(callback_type(), any(), map()) :: {:ok, any()} | {:halt, any()}
  def execute(type, value, context) do
    ensure_initialized()

    case :ets.lookup(@callback_registry_name, type) do
      [] ->
        # No callbacks registered for this type
        {:ok, value}

      [{^type, callbacks}] ->
        # Filter and execute callbacks
        execute_callbacks(callbacks, value, context)
    end
  end

  # Private functions

  defp ensure_initialized do
    case :ets.info(@callback_registry_name) do
      :undefined -> init()
      _ -> :ok
    end
  end

  defp execute_callbacks(callbacks, initial_value, context) do
    # Find applicable callbacks based on the context
    applicable_callbacks =
      Enum.filter(callbacks, fn {_, _, filter} ->
        matches_filter?(filter, context)
      end)

    # Execute callbacks in sequence, passing the result of each to the next
    Enum.reduce_while(applicable_callbacks, {:ok, initial_value}, fn {_, callback, _},
                                                                     {:ok, value} ->
      try do
        case callback.(value, context) do
          {:cont, new_value} ->
            {:cont, {:ok, new_value}}

          {:halt, final_value} ->
            {:halt, {:halt, final_value}}

          other ->
            Logger.warning(
              "Callback returned invalid format: #{inspect(other)}, expected {:cont, value} or {:halt, value}"
            )

            {:cont, {:ok, value}}
        end
      rescue
        e ->
          Logger.error("Error in callback: #{inspect(e)}")
          {:cont, {:ok, value}}
      end
    end)
  end

  defp matches_filter?(callback_filter, context) do
    Enum.all?(callback_filter, fn {key, value} ->
      Map.get(context, key) == value
    end)
  end
end
