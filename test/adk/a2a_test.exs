defmodule Adk.A2ATest do
  use ExUnit.Case, async: true

  alias Adk.A2A

  describe "send_message/3" do
    test "returns a valid envelope with correct fields" do
      recipient = :agent_b
      payload = %{foo: "bar"}
      opts = %{type: :custom_type, sender: :agent_a, metadata: %{trace: true}}
      {:ok, env} = A2A.send_message(recipient, payload, opts)
      assert env.recipient == recipient
      assert env.payload == payload
      assert env.type == :custom_type
      assert env.sender == :agent_a
      assert env.metadata == %{trace: true}
      assert is_binary(env.id)
      assert %NaiveDateTime{} = env.timestamp
    end

    test "defaults type and sender if not provided" do
      {:ok, env} = A2A.send_message(:agent, "hi", %{})
      assert env.type == "a2a_message"
      assert env.sender == self()
    end
  end

  describe "handle_message/2" do
    test "returns {:ok, {payload, state}}" do
      env = %{payload: 123}
      state = :foo
      assert {:ok, {123, :foo}} == A2A.handle_message(env, state)
    end
  end

  describe "call_local/3" do
    test "calls runner and adds metadata" do
      runner = fn agent, input -> {:ok, %{agent: agent, input: input}} end
      result = A2A.call_local(:agent, "input", %{foo: 1}, runner)
      assert {:ok, map} = result
      assert map.agent == :agent
      assert map.input == "input"
      assert map.metadata == %{foo: 1}
    end
  end

  describe "call_remote/4" do
    test "returns mock response with metadata" do
      {:ok, resp} = A2A.call_remote("http://x", "input", %{foo: 2}, [])
      assert resp.output =~ "Mock response"
      assert resp.metadata == %{foo: 2}
    end
  end

  describe "register_http/2" do
    test "returns :ok" do
      assert :ok == A2A.register_http(:agent, "/foo")
    end
  end
end
