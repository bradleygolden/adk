defmodule Adk.LLM do
  @moduledoc """
  Provides utilities for working with Language Models (LLMs).

  ## Configuration

      config :adk, :llm_provider, :mock

  By default, the mock provider is used. You can override this in your config (e.g., :langchain, :openai, or a custom module).

  ## Usage

  You can call LLM functions with or without specifying the provider. If omitted, the configured provider is used:

      Adk.LLM.complete("Tell me a joke")
      Adk.LLM.complete(:mock, "Tell me a joke")
      Adk.LLM.complete(MyCustomProvider, "Tell me a joke")
  """

  @type provider :: atom() | module()
  @type prompt :: String.t()
  @type options :: map()
  @type messages :: [map()]
  @type completion_result :: {:ok, String.t()} | {:error, {:completion_failed, term()}}
  @type chat_result ::
          {:ok, %{content: String.t() | nil, tool_calls: list(map()) | nil}}
          | {:error, {:chat_failed, term()}}

  @doc """
  Complete a prompt using the configured or specified LLM provider.
  """
  @spec complete(prompt) :: completion_result
  def complete(prompt), do: complete(resolve_provider(), prompt, %{})

  @doc """
  Complete a prompt using the specified LLM provider and options.
  """
  @spec complete(provider, prompt, options) :: completion_result
  def complete(provider, prompt, options \\ %{}) do
    with {:ok, provider_module} <- get_provider_module(provider) do
      provider_module.complete(prompt, options)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generate a chat response using the configured or specified LLM provider.
  """
  @spec chat(messages) :: chat_result
  def chat(messages), do: chat(resolve_provider(), messages, %{})

  @doc """
  Generate a chat response using the specified LLM provider and options.
  """
  @spec chat(provider, messages, options) :: chat_result
  def chat(provider, messages, options \\ %{}) do
    with {:ok, provider_module} <- get_provider_module(provider) do
      provider_module.chat(messages, options)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the configuration for a provider (or the configured default).
  """
  @spec config() :: map() | {:error, term()}
  def config, do: config(resolve_provider())

  @doc """
  Get the configuration for a specific provider.
  """
  @spec config(provider) :: map() | {:error, term()}
  def config(provider) do
    with {:ok, provider_module} <- get_provider_module(provider) do
      provider_module.config()
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp resolve_provider do
    Application.get_env(:adk, :llm_provider, :mock)
  end

  defp get_provider_module(provider) when is_atom(provider) do
    cond do
      Code.ensure_loaded?(provider) ->
        {:ok, provider}

      provider == :mock && Code.ensure_loaded?(Adk.LLM.Providers.Mock) ->
        {:ok, Adk.LLM.Providers.Mock}

      provider == :langchain ->
        {:ok, Adk.LLM.Providers.Langchain}

      # :openai -> {:ok, Adk.LLM.Providers.OpenAI} # Assuming these might exist later
      # :anthropic -> {:ok, Adk.LLM.Providers.Anthropic}
      true ->
        {:error, {:unknown_provider, provider}}
    end
  end

  # Handle cases where a non-atom is passed
  defp get_provider_module(provider) do
    {:error, {:invalid_provider_type, provider}}
  end
end
