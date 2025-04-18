defmodule Adk.EventTest do
  use ExUnit.Case, async: true

  alias Adk.Event

  describe "new/1" do
    test "creates an event with required fields" do
      event = Event.new(session_id: "sess1", author: :user)
      assert event.session_id == "sess1"
      assert event.author == :user
      assert is_binary(event.id)
      assert %NaiveDateTime{} = event.timestamp
    end

    test "sets and serializes type and payload fields" do
      event =
        Event.new(session_id: "sess1", author: :user, type: "user_message", payload: %{foo: 1})

      assert event.type == "user_message"
      assert event.payload == %{foo: 1}
      {:ok, json} = Event.to_json(event)
      assert json =~ "user_message"
      assert json =~ "foo"
    end

    test "allows custom id and timestamp" do
      now = ~N[2024-01-01 12:00:00]
      event = Event.new(session_id: "sess1", author: :user, id: "custom", timestamp: now)
      assert event.id == "custom"
      assert event.timestamp == now
    end

    test "returns nil for missing required fields" do
      event = Event.new(%{author: :user})
      assert event.session_id == nil
      assert event.author == :user

      event2 = Event.new(%{session_id: "sess1"})
      assert event2.session_id == "sess1"
      assert event2.author == nil
    end
  end

  describe "JSON encoding/decoding" do
    test "encodes and decodes event struct (round trip)" do
      event =
        Event.new(
          session_id: "sess2",
          author: :model,
          type: "model_response",
          payload: %{bar: 2},
          content: %{foo: "bar"}
        )

      {:ok, json} = Event.to_json(event)
      assert is_binary(json)
      {:ok, decoded} = Event.from_json(json)
      assert %Adk.Event{} = decoded
      assert decoded.session_id == "sess2"
      assert decoded.author == :model
      assert decoded.type == "model_response"
      assert decoded.payload == %{"bar" => 2}
      assert decoded.content == %{"foo" => "bar"}
    end

    test "to_json returns error for non-serializable struct" do
      # Functions are not serializable
      bad_struct = %{foo: fn -> :bar end}
      assert {:error, _} = Event.to_json(bad_struct)
    end

    test "from_json returns error for invalid JSON" do
      assert {:error, _} = Event.from_json("not valid json")
    end
  end

  describe "edge cases" do
    test "handles nil content, tool_calls, tool_results, type, payload" do
      event = Event.new(session_id: "sess3", author: :tool)
      assert event.content == nil
      assert event.tool_calls == nil
      assert event.tool_results == nil
      assert event.type == nil
      assert event.payload == nil
    end
  end

  describe "subscribe/unsubscribe/publish" do
    test "can subscribe and receive events" do
      # Subscribe to events
      {:ok, pid} = Event.subscribe()
      assert pid == self()

      # Create and publish an event
      event = Event.new(session_id: "test_session", author: :user, content: "test message")
      Event.publish(event)

      # Check that we received the event
      assert_receive {:adk_event, received_event}
      assert received_event.session_id == "test_session"
      assert received_event.content == "test message"
    end

    test "unsubscribe stops receiving events" do
      # Subscribe, then unsubscribe
      {:ok, pid} = Event.subscribe()
      :ok = Event.unsubscribe(pid)

      # Publish an event
      event = Event.new(session_id: "test_session", author: :user, content: "test message")
      Event.publish(event)

      # Should not receive the event
      refute_receive {:adk_event, _}, 100
    end

    test "unsubscribe is idempotent" do
      # Unsubscribe when not subscribed should be fine
      :ok = Event.unsubscribe(self())

      # Subscribe, unsubscribe multiple times
      {:ok, _pid} = Event.subscribe()
      :ok = Event.unsubscribe(self())
      # Second unsubscribe should be a no-op
      :ok = Event.unsubscribe(self())

      # Publish an event
      event = Event.new(session_id: "test_session", author: :user)
      Event.publish(event)

      # Should not receive the event
      refute_receive {:adk_event, _}, 100
    end

    test "publish returns :ok when no subscribers" do
      # Make sure we're not subscribed
      Event.unsubscribe(self())

      # Publish an event with no subscribers
      event = Event.new(session_id: "test_session", author: :user)
      result = Event.publish(event)

      # Should return :ok
      assert result == :ok
    end
  end
end
