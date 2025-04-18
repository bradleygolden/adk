defmodule Adk.LLMTest do
  use ExUnit.Case, async: true

  # A test module to verify custom provider behavior
  defmodule TestProvider do
    @behaviour Adk.LLM.Provider

    def complete(_prompt, _opts) do
      {:ok, "TestProvider response"}
    end

    def chat(_messages, _opts) do
      {:ok, %{content: "TestProvider chat response", tool_calls: []}}
    end

    def config do
      %{name: "test_provider"}
    end
  end

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

  describe "custom provider module" do
    test "complete/3 with custom module" do
      assert {:ok, response} = Adk.LLM.complete(TestProvider, "Test prompt", %{})
      assert response == "TestProvider response"
    end

    test "chat/3 with custom module" do
      messages = [%{role: "user", content: "Hello"}]

      assert {:ok, %{content: content, tool_calls: calls}} =
               Adk.LLM.chat(TestProvider, messages, %{})

      assert content == "TestProvider chat response"
      assert calls == []
    end

    test "config/1 with custom module" do
      config = Adk.LLM.config(TestProvider)
      assert config[:name] == "test_provider"
    end
  end

  describe "error handling" do
    test "complete/3 with unknown provider" do
      assert {:error, {:unknown_provider, :nonexistent_provider}} =
               Adk.LLM.complete(:nonexistent_provider, "Test prompt", %{})
    end

    test "chat/3 with unknown provider" do
      assert {:error, {:unknown_provider, :nonexistent_provider}} =
               Adk.LLM.chat(:nonexistent_provider, [%{role: "user", content: "Hello"}], %{})
    end

    test "config/1 with unknown provider" do
      assert {:error, {:unknown_provider, :nonexistent_provider}} =
               Adk.LLM.config(:nonexistent_provider)
    end

    test "complete/3 with invalid provider type" do
      assert {:error, {:invalid_provider_type, "not_an_atom"}} =
               Adk.LLM.complete("not_an_atom", "Test prompt", %{})
    end

    test "chat/3 with invalid provider type" do
      assert {:error, {:invalid_provider_type, "not_an_atom"}} =
               Adk.LLM.chat("not_an_atom", [%{role: "user", content: "Hello"}], %{})
    end

    test "config/1 with invalid provider type" do
      assert {:error, {:invalid_provider_type, "not_an_atom"}} =
               Adk.LLM.config("not_an_atom")
    end
  end
end
