defmodule Adk.LLM.Providers.Mock do
  @moduledoc """
  Deterministic mock LLM provider for testing Adk agent workflows.

  This module implements the `Adk.LLM.Provider` behaviour and is intended for deterministic and customizable testing of Adk agents and workflows.

  ## Configuration

      config :adk, :llm_provider, :mock

  ## Supported Options
  - `:mock_response` (string): If provided, this value will be returned as the LLM response for both `complete/2` and `chat/2`.

  ## Usage
  Use this provider to simulate LLM completions and chat responses in tests. You can override the response by passing `mock_response` in the options map.

  ## Extension Points
  - Provide custom mock responses via options for different test scenarios.
  - Extend to simulate tool calls or error conditions as needed.
  - See https://google.github.io/adk-docs/LLM for design rationale.
  """
  use Adk.LLM.Provider

  @doc """
  Returns a mock completion response. If `:mock_response` is provided in options, it is returned; otherwise, a default mock response is generated.
  """
  @impl true
  def complete(prompt, options) do
    response =
      case Map.get(options, :mock_response) do
        nil -> "Mock response for: #{prompt}"
        custom -> custom
      end

    {:ok, response}
  end

  @doc """
  Returns a mock chat response. If `:mock_response` is provided in options, it is returned; otherwise, a default mock response is generated based on the last user message.
  """
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

    {:ok, %{role: "assistant", content: content, tool_calls: nil}}
  end

  @impl true
  def config do
    %{
      name: "mock",
      description: "A mock LLM provider for testing"
    }
  end
end
