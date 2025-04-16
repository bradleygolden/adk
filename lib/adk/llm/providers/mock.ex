defmodule Adk.LLM.Providers.Mock do
  @moduledoc """
  A mock LLM provider for testing purposes.
  """
  use Adk.LLM.Provider

  @impl true
  def complete(prompt, options) do
    response =
      case Map.get(options, :mock_response) do
        nil -> "Mock response for: #{prompt}"
        custom -> custom
      end

    {:ok, response}
  end

  @impl true
  def chat(messages, options) do
    # Extract the last user message
    last_user_message =
      messages
      |> Enum.reverse()
      |> Enum.find(fn msg -> msg.role == "user" end)

    content =
      case last_user_message do
        nil -> "No user message found"
        msg -> "Mock response to: #{msg.content}"
      end

    # Use custom response if provided
    content =
      case Map.get(options, :mock_response) do
        nil -> content
        custom -> custom
      end

    {:ok, %{role: "assistant", content: content}}
  end

  @impl true
  def config do
    %{
      name: "mock",
      description: "A mock LLM provider for testing"
    }
  end
end
