defmodule Adk.LLM.Provider do
  @moduledoc """
  Behavior and utilities for LLM providers in the ADK framework.
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
