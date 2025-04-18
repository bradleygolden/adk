defmodule Adk.Callback.Helpers do
  @moduledoc """
  Helper functions for working with the Adk callback system.

  This module provides pre-built callback functions for common patterns like
  logging, telemetry, and data transformation.

  ## Examples

  ```elixir
  # Add a logging callback for all agent runs
  Adk.Callback.register(:before_run, Adk.Callback.Helpers.log_callback("Processing input"))

  # Add a callback that modifies the input
  Adk.Callback.register(:before_run, Adk.Callback.Helpers.transform_callback(fn input, _ctx ->
    # Add a timestamp to the input
    Map.put(input, :timestamp, DateTime.utc_now())
  end))
  ```
  """

  require Logger

  @doc """
  Creates a callback function that logs information about the callback execution.

  ## Parameters

  - `message`: A string message to log
  - `level`: The log level (default: `:info`)

  ## Returns

  A callback function that logs and continues with the original value.
  """
  def log_callback(message, level \\ :info) do
    fn value, context ->
      log_fn =
        case level do
          :debug -> &Logger.debug/1
          :info -> &Logger.info/1
          :warning -> &Logger.warning/1
          :error -> &Logger.error/1
          _ -> &Logger.info/1
        end

      # Format context values for logging
      agent_name = Map.get(context, :agent_name, "unknown")
      type = Map.get(context, :callback_type, "callback")

      log_fn.("#{message} [Agent: #{agent_name}] [#{type}]")

      {:cont, value}
    end
  end

  @doc """
  Creates a callback function that applies a transform to the value.

  ## Parameters

  - `transform_fn`: A function that takes (value, context) and returns a new value

  ## Returns

  A callback function that transforms the value and continues.
  """
  def transform_callback(transform_fn) when is_function(transform_fn, 2) do
    fn value, context ->
      {:cont, transform_fn.(value, context)}
    end
  end

  @doc """
  Creates a callback function that validates the value against a predicate.

  ## Parameters

  - `predicate_fn`: A function that takes a value and returns true/false
  - `error_message`: The error message to return if validation fails

  ## Returns

  A callback function that either continues if validation passes, or halts with an error.
  """
  def validate_callback(predicate_fn, error_message) when is_function(predicate_fn, 1) do
    fn value, _context ->
      if predicate_fn.(value) do
        {:cont, value}
      else
        {:halt, {:error, {:validation_failed, error_message}}}
      end
    end
  end

  @doc """
  Creates a callback function that emits a telemetry event.

  ## Parameters

  - `event_name`: The telemetry event name (list of atoms)
  - `measurements_fn`: A function that takes (value, context) and returns measurements map

  ## Returns

  A callback function that emits a telemetry event and continues.
  """
  def telemetry_callback(event_name, measurements_fn \\ &default_measurements/2)
      when is_list(event_name) do
    fn value, context ->
      measurements = measurements_fn.(value, context)

      metadata = %{
        agent_name: Map.get(context, :agent_name),
        session_id: Map.get(context, :session_id),
        invocation_id: Map.get(context, :invocation_id)
      }

      :telemetry.execute(event_name, measurements, metadata)

      {:cont, value}
    end
  end

  @doc """
  Creates a callback function that caches the value in memory.

  ## Parameters

  - `key_fn`: A function that derives a cache key from the value and context

  ## Returns

  A callback function that stores the value in memory and continues.
  """
  def cache_callback(key_fn) when is_function(key_fn, 2) do
    fn value, context ->
      key = key_fn.(value, context)
      session_id = Map.get(context, :session_id)

      if key && session_id do
        case Adk.Memory.get_service_module(Adk.Memory.resolve_backend()) do
          service when is_atom(service) ->
            apply(service, :update_state, [session_id, key, value])

          _ ->
            :ok
        end
      end

      {:cont, value}
    end
  end

  # Private helpers

  defp default_measurements(_value, _context) do
    %{timestamp: System.system_time(:millisecond)}
  end
end
