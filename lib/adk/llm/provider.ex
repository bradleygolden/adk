defmodule Adk.LLM.Provider do
  @moduledoc """
  Behavior and utilities for LLM providers in the ADK framework.
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type completion_result :: {:ok, String.t()} | {:error, term()}
  @type chat_result :: {:ok, message()} | {:error, term()}

  @doc """
  Generate a completion from the LLM based on a prompt.
  """
  @callback complete(prompt :: String.t(), options :: map()) :: completion_result()

  @doc """
  Generate a response from the LLM based on a list of chat messages.
  """
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
      defoverridable [config: 0]
    end
  end
end