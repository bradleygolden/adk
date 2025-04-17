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
end
