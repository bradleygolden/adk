defmodule Adk.Test.MockLLMProvider do
  @moduledoc """
  A mock LLM provider for testing purposes.
  Allows setting expected responses via the process dictionary.
  """
  @behaviour Adk.LLM.Provider

  # Expected response is now stored in Adk.Test.MockLLMStateAgent

  @impl true
  def chat(_messages, _opts) do
    # Get response from the state agent, default if nil
    content = Adk.Test.MockLLMStateAgent.get_response() || "Default mock response"
    {:ok, %{content: content, tool_calls: nil}}
  end

  # Implement required callbacks
  @impl true
  def complete(_prompt, _opts) do
    # Return a simple mock completion
    {:ok, "Mock completion"}
  end

  @impl true
  def config() do
    # Return basic mock config
    %{name: "mock_provider"}
  end

  # Remove @impl from functions not in the behaviour
  def models(_opts), do: {:ok, ["mock-model"]}

  def validate_config(_config), do: :ok
end
