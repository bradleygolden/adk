defmodule Adk.TelemetryTest do
  use ExUnit.Case, async: false

  alias Adk.Telemetry
  require Logger

  @test_event [:adk, :test, :event]
  @test_span_event [:adk, :test, :span]

  setup do
    # Detach any existing handlers to ensure clean test environment
    :ok = detach_all_handlers()
    :ok
  end

  test "execute emits a basic telemetry event" do
    test_pid = self()
    ref = make_ref()

    # Attach a handler for the test event
    :ok =
      :telemetry.attach(
        "test-handler",
        @test_event,
        fn name, measurements, metadata, _config ->
          send(test_pid, {:event_received, ref, name, measurements, metadata})
        end,
        nil
      )

    # Emit the event
    test_measurements = %{value: 42}
    test_metadata = %{source: "test"}

    Telemetry.execute(@test_event, test_measurements, test_metadata)

    # Assert the event was received with correct data
    assert_receive {:event_received, ^ref, @test_event, received_measurements, received_metadata}
    assert received_measurements.value == 42
    assert received_metadata.source == "test"
  end

  test "span emits start and stop events with duration" do
    test_pid = self()
    ref = make_ref()

    # Track received events
    start_event = @test_span_event ++ [:start]
    stop_event = @test_span_event ++ [:stop]

    # Attach handlers for span events
    :ok =
      :telemetry.attach_many(
        "test-span-handler",
        [start_event, stop_event],
        fn name, measurements, metadata, _config ->
          send(test_pid, {:span_event, ref, name, measurements, metadata})
        end,
        nil
      )

    # Execute a span with a function that sleeps
    test_metadata = %{span_id: "test-span"}

    result =
      Telemetry.span(@test_span_event, test_metadata, fn ->
        :timer.sleep(50)
        {:ok, "result"}
      end)

    # Assert span function result
    assert result == {:ok, "result"}

    # Assert start event
    assert_receive {:span_event, ^ref, ^start_event, start_measurements, start_metadata}
    assert is_integer(start_measurements.system_time)
    assert start_metadata.span_id == "test-span"

    # Assert stop event
    assert_receive {:span_event, ^ref, ^stop_event, stop_measurements, stop_metadata}
    assert is_integer(stop_measurements.duration)
    # At least 50ms
    assert stop_measurements.duration >= 50
    assert stop_metadata.span_id == "test-span"
    # Result type captured
    assert stop_metadata.result == :ok
  end

  test "span captures exceptions and re-raises them" do
    test_pid = self()
    ref = make_ref()

    # Track received events
    exception_event = @test_span_event ++ [:exception]

    # Attach handlers for exception event
    :ok =
      :telemetry.attach(
        "test-exception-handler",
        exception_event,
        fn name, measurements, metadata, _config ->
          send(test_pid, {:exception_event, ref, name, measurements, metadata})
        end,
        nil
      )

    # Execute a span with a function that raises
    test_metadata = %{span_id: "error-span"}

    assert_raise RuntimeError, "test error", fn ->
      Telemetry.span(@test_span_event, test_metadata, fn ->
        :timer.sleep(50)
        raise "test error"
      end)
    end

    # Assert exception event
    assert_receive {:exception_event, ^ref, ^exception_event, measurements, metadata}
    assert is_integer(measurements.duration)
    # At least 50ms
    assert measurements.duration >= 50
    assert metadata.span_id == "error-span"
    assert %RuntimeError{message: "test error"} = metadata.error
    assert is_list(metadata.stacktrace)
    assert metadata.kind == :error
  end

  test "attach_handler and detach_handler work correctly" do
    test_pid = self()
    ref = make_ref()

    # Define a handler function
    handler_fn = fn _name, _measurements, _metadata, _config ->
      send(test_pid, {:handler_called, ref})
    end

    # Attach the handler
    :ok = Telemetry.attach_handler("test-attach", @test_event, handler_fn)

    # Emit an event
    Telemetry.execute(@test_event)
    assert_receive {:handler_called, ^ref}

    # Detach the handler
    :ok = Telemetry.detach_handler("test-attach")

    # Emit another event - should not be received
    Telemetry.execute(@test_event)
    refute_receive {:handler_called, ^ref}
  end

  test "attach_many_handlers works with multiple events" do
    test_pid = self()
    ref = make_ref()

    # Define a list of events
    events = [
      [:adk, :test, :event1],
      [:adk, :test, :event2],
      [:adk, :test, :event3]
    ]

    # Define a handler function
    handler_fn = fn name, _measurements, _metadata, _config ->
      send(test_pid, {:many_handler_called, ref, name})
    end

    # Attach the handler to multiple events
    :ok = Telemetry.attach_many_handlers("test-many", events, handler_fn)

    # Emit events
    Enum.each(events, &Telemetry.execute/1)

    # Assert all events were handled
    Enum.each(events, fn event ->
      assert_receive {:many_handler_called, ^ref, ^event}
    end)

    # Detach the handler
    :ok = Telemetry.detach_handler("test-many")
  end

  test "event helpers return expected event lists" do
    assert is_list(Telemetry.agent_events())
    assert length(Telemetry.agent_events()) == 3

    assert Enum.all?(Telemetry.agent_events(), fn event ->
             List.first(event) == :adk && Enum.at(event, 1) == :agent
           end)

    assert is_list(Telemetry.llm_events())
    assert length(Telemetry.llm_events()) == 3

    assert Enum.all?(Telemetry.llm_events(), fn event ->
             List.first(event) == :adk && Enum.at(event, 1) == :llm
           end)

    assert is_list(Telemetry.tool_events())
    assert length(Telemetry.tool_events()) == 3

    assert Enum.all?(Telemetry.tool_events(), fn event ->
             List.first(event) == :adk && Enum.at(event, 1) == :tool
           end)

    all_events = Telemetry.all_events()
    assert is_list(all_events)
    assert length(all_events) == 9
    assert Enum.all?(all_events, fn event -> List.first(event) == :adk end)
  end

  # Helper function to detach all handlers in the test
  defp detach_all_handlers do
    # Get all handlers for these test events
    test_event_patterns = [
      [:adk, :test, :*],
      [:adk, :agent, :*],
      [:adk, :llm, :*],
      [:adk, :tool, :*]
    ]

    # Detach matching handlers - this is a bit brute force but ensures clean tests
    for {handler_id, event_patterns, _, _} <- :telemetry.list_handlers([]) do
      if Enum.any?(test_event_patterns, fn pattern ->
           pattern_matches?(event_patterns, pattern)
         end) do
        :telemetry.detach(handler_id)
      end
    end

    :ok
  end

  # Check if a handler's event pattern would match our test pattern
  defp pattern_matches?(handler_events, test_pattern) do
    Enum.any?(handler_events, fn event ->
      match_event?(event, test_pattern)
    end)
  end

  defp match_event?([], []) do
    true
  end

  defp match_event?([_h1 | _t1], [:* | []]) do
    true
  end

  defp match_event?([h1 | t1], [h2 | t2]) when h1 == h2 do
    match_event?(t1, t2)
  end

  defp match_event?(_, _) do
    false
  end
end
