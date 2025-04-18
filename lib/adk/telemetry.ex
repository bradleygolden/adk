defmodule Adk.Telemetry do
  @moduledoc """
  Telemetry integration for the Adk framework.

  This module defines standard telemetry events emitted by the Adk framework
  and provides utilities for attaching handlers and emitting events.

  ## Event Naming

  All Adk telemetry events use the prefix `[:adk]` followed by component and action:

  - `[:adk, :agent, :run, :start]` - When an agent begins processing input
  - `[:adk, :agent, :run, :stop]` - When an agent completes processing
  - `[:adk, :agent, :run, :exception]` - When an agent raises an exception

  - `[:adk, :llm, :call, :start]` - When an LLM call begins
  - `[:adk, :llm, :call, :stop]` - When an LLM call completes
  - `[:adk, :llm, :call, :exception]` - When an LLM call raises an exception

  - `[:adk, :tool, :call, :start]` - When a tool call begins
  - `[:adk, :tool, :call, :stop]` - When a tool call completes
  - `[:adk, :tool, :call, :exception]` - When a tool call raises an exception
  """

  require Logger

  @doc """
  Attaches a handler to a specific Adk telemetry event.

  ## Parameters

  - `handler_id`: Unique identifier for the handler
  - `event_name`: Telemetry event name (list of atoms)
  - `handler_function`: Function with arity 4 that receives the event measurements, metadata, and config
  - `config`: Optional configuration passed to the handler function

  ## Returns

  `:ok` if the handler was attached successfully,
  `{:error, :already_exists}` if a handler with that ID already exists
  """
  @spec attach_handler(
          handler_id :: term(),
          event_name :: [atom(), ...],
          handler_function :: (map(), map(), term(), term() -> any()),
          config :: term()
        ) :: :ok | {:error, :already_exists}
  def attach_handler(handler_id, event_name, handler_function, config \\ nil) do
    :telemetry.attach(handler_id, event_name, handler_function, config)
  end

  @doc """
  Attaches a handler to multiple Adk telemetry events.

  ## Parameters

  - `handler_id`: Unique identifier for the handler
  - `event_names`: List of telemetry event names (each a list of atoms)
  - `handler_function`: Function with arity 4 that receives the event measurements, metadata, and config
  - `config`: Optional configuration passed to the handler function

  ## Returns

  `:ok` if the handler was attached successfully,
  `{:error, :already_exists}` if a handler with that ID already exists
  """
  @spec attach_many_handlers(
          handler_id :: term(),
          event_names :: [[atom(), ...]],
          handler_function :: (map(), map(), term(), term() -> any()),
          config :: term()
        ) :: :ok | {:error, :already_exists}
  def attach_many_handlers(handler_id, event_names, handler_function, config \\ nil) do
    :telemetry.attach_many(handler_id, event_names, handler_function, config)
  end

  @doc """
  Detaches a telemetry handler by its ID.

  ## Parameters

  - `handler_id`: The ID of the handler to detach

  ## Returns

  `:ok` if the handler was detached successfully
  """
  @spec detach_handler(handler_id :: term()) :: :ok
  def detach_handler(handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Executes a function within a telemetry span, automatically emitting
  start, stop, and exception events with timing information.

  ## Parameters

  - `event_prefix`: Prefix for the telemetry events (without :start/:stop/:exception suffixes)
  - `metadata`: Additional metadata to include with the telemetry events
  - `function`: The function to execute within the span

  ## Returns

  The return value of the executed function, or re-raises any exceptions after
  emitting an exception event.

  ## Events Emitted

  - `event_prefix ++ [:start]` - When the span begins
  - `event_prefix ++ [:stop]` - When the span completes successfully
  - `event_prefix ++ [:exception]` - When the span raises an exception
  """
  @spec span([atom(), ...], map(), (-> any())) :: any()
  def span(event_prefix, metadata \\ %{}, function) when is_function(function, 0) do
    start_time = System.monotonic_time()
    start_event = event_prefix ++ [:start]

    :telemetry.execute(start_event, %{system_time: System.system_time()}, metadata)

    try do
      result = function.()
      end_time = System.monotonic_time()
      stop_event = event_prefix ++ [:stop]

      measurements = %{
        duration: System.convert_time_unit(end_time - start_time, :native, :millisecond),
        monotonic_time: end_time,
        system_time: System.system_time()
      }

      result_metadata =
        case result do
          {:ok, _} -> Map.put(metadata, :result, :ok)
          {:error, _} -> Map.put(metadata, :result, :error)
          _ -> metadata
        end

      :telemetry.execute(stop_event, measurements, result_metadata)
      result
    rescue
      exception ->
        end_time = System.monotonic_time()
        exception_event = event_prefix ++ [:exception]

        measurements = %{
          duration: System.convert_time_unit(end_time - start_time, :native, :millisecond),
          monotonic_time: end_time,
          system_time: System.system_time()
        }

        exception_metadata =
          metadata
          |> Map.put(:kind, :error)
          |> Map.put(:error, exception)
          |> Map.put(:stacktrace, __STACKTRACE__)

        :telemetry.execute(exception_event, measurements, exception_metadata)
        reraise exception, __STACKTRACE__
    end
  end

  @doc """
  Emits a simple telemetry event with the given name, measurements, and metadata.

  ## Parameters

  - `event_name`: The full telemetry event name
  - `measurements`: Map of measurements for the event (default: current system time)
  - `metadata`: Additional metadata for the event

  ## Returns

  `:ok`
  """
  @spec execute([atom(), ...], map(), map()) :: :ok
  def execute(event_name, measurements \\ %{}, metadata \\ %{}) do
    measurements =
      if map_size(measurements) == 0 do
        %{system_time: System.system_time()}
      else
        measurements
      end

    :telemetry.execute(event_name, measurements, metadata)
  end

  @doc """
  Returns a list of standard event names for agent operations.
  Useful for attaching handlers to all agent-related events.
  """
  @spec agent_events() :: [[atom(), ...]]
  def agent_events do
    [
      [:adk, :agent, :run, :start],
      [:adk, :agent, :run, :stop],
      [:adk, :agent, :run, :exception]
    ]
  end

  @doc """
  Returns a list of standard event names for LLM operations.
  Useful for attaching handlers to all LLM-related events.
  """
  @spec llm_events() :: [[atom(), ...]]
  def llm_events do
    [
      [:adk, :llm, :call, :start],
      [:adk, :llm, :call, :stop],
      [:adk, :llm, :call, :exception]
    ]
  end

  @doc """
  Returns a list of standard event names for tool operations.
  Useful for attaching handlers to all tool-related events.
  """
  @spec tool_events() :: [[atom(), ...]]
  def tool_events do
    [
      [:adk, :tool, :call, :start],
      [:adk, :tool, :call, :stop],
      [:adk, :tool, :call, :exception]
    ]
  end

  @doc """
  Returns a list of all standard Adk telemetry events.
  Useful for attaching handlers to all Adk framework events.
  """
  @spec all_events() :: [[atom(), ...]]
  def all_events do
    agent_events() ++ llm_events() ++ tool_events()
  end
end
