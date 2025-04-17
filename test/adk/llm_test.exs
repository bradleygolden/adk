defmodule Adk.LLMTest do
  use ExUnit.Case, async: true

  describe "default provider resolution" do
    setup do
      # Save the original config and set the provider to :mock for these tests
      original = Application.get_env(:adk, :llm_provider)
      Application.put_env(:adk, :llm_provider, :mock)

      on_exit(fn ->
        if original do
          Application.put_env(:adk, :llm_provider, original)
        else
          Application.delete_env(:adk, :llm_provider)
        end
      end)

      :ok
    end

    test "complete/1 uses the configured default provider" do
      assert {:ok, response} = Adk.LLM.complete("Test prompt")
      assert is_binary(response)
      assert String.contains?(response, "Mock")
    end

    test "chat/1 uses the configured default provider" do
      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, %{content: content, tool_calls: nil}} = Adk.LLM.chat(messages)
      assert is_binary(content)
      assert String.contains?(content, "Mock")
    end

    test "config/0 returns the default provider config" do
      config = Adk.LLM.config()
      assert is_map(config)
      assert config[:name] == "mock"
    end
  end

  describe "explicit provider argument" do
    test "complete/3 with :mock provider" do
      assert {:ok, response} = Adk.LLM.complete(:mock, "Test prompt", %{})
      assert is_binary(response)
      assert String.contains?(response, "Mock")
    end

    test "chat/3 with :mock provider" do
      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, %{content: content, tool_calls: nil}} = Adk.LLM.chat(:mock, messages, %{})
      assert is_binary(content)
      assert String.contains?(content, "Mock")
    end

    test "config/1 with :mock provider" do
      config = Adk.LLM.config(:mock)
      assert is_map(config)
      assert config[:name] == "mock"
    end
  end
end
