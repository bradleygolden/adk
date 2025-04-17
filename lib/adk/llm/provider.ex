defmodule Adk.LLM.Provider do
  @moduledoc """
  Behaviour and utilities for LLM providers in the Adk framework.

  ## Purpose

  This module defines the contract for integrating Large Language Model (LLM) providers into the Agent Development Kit (ADK). All LLM providers must implement this behaviour to ensure consistent invocation and compatibility.

  ## Provider Implementation

      defmodule MyApp.LLMProviders.MyProvider do
        use Adk.LLM.Provider

        @impl true
        def complete(prompt, options) do
          # Implement provider-specific completion logic
          {:ok, "Completion for: ..."}
        end

        @impl true
        def chat(messages, options) do
          # Implement provider-specific chat logic
          {:ok, %{content: "Chat response", tool_calls: nil}}
        end

        @impl true
        def config do
          %{
            name: "my_provider",
            description: "Custom LLM provider for MyApp"
          }
        end
      end

  ## Dynamic Dispatch and Usage

  Dynamic dispatch and provider selection is handled by `Adk.LLM`, not this module. Use `Adk.LLM.complete/1,2,3` and `Adk.LLM.chat/1,2,3` to invoke the configured or specified provider. See `Adk.LLM` for details on provider selection and configuration.

      # Example usage (see Adk.LLM docs):
      Adk.LLM.complete("Tell me a joke")
      Adk.LLM.chat([%{role: "user", content: "Hello!"}])

  ## Rationale

  - Ensures all LLM providers expose a uniform API for prompt and chat-based completions.
  - Supports tool-calling and advanced agent workflows.
  - Enables dynamic dispatch and registry of providers via configuration (see `Adk.LLM`).

  See https://google.github.io/adk-docs/LLM for design rationale and best practices.
  """

  # Reverted message type to original, only changing chat_result
  @type message :: %{
          required(:role) => String.t(),
          required(:content) => String.t(),
          optional(:tool_calls) => list(map()),
          optional(:tool_call_id) => String.t(),
          optional(:name) => String.t()
        }
  @type completion_result :: {:ok, String.t()} | {:error, {:completion_failed, reason :: term()}}
  # Updated chat_result to potentially include tool calls and descriptive error
  @type chat_result ::
          {:ok, %{content: String.t() | nil, tool_calls: list(map()) | nil}}
          | {:error, {:chat_failed, reason :: term()}}

  @doc """
  Generate a completion from the LLM based on a prompt.
  """
  @callback complete(prompt :: String.t(), options :: map()) :: completion_result()

  @doc """
  Generate a response from the LLM based on a list of chat messages.
  """
  # Updated callback signature to reflect the new chat_result type
  @callback chat(messages :: [message()], options :: map()) :: chat_result()

  @doc """
  Get the provider's configuration.
  """
  @callback config() :: map()

  @doc """
  Macro to implement common LLM provider functionality.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Adk.LLM.Provider

      # Default implementation
      @impl Adk.LLM.Provider
      def config do
        %{}
      end

      # Allow overriding default implementations
      defoverridable config: 0
    end
  end
end
