defmodule Adk.LLM do
  @moduledoc """
  Provides utilities for working with Language Models.
  """

  @doc """
  Complete a prompt using the specified LLM provider.

  ## Parameters
    * `provider` - The LLM provider to use (atom or module)
    * `prompt` - The prompt to complete
    * `options` - Optional configuration for the provider

  ## Examples
      iex> Adk.LLM.complete(:openai, "Tell me a joke", %{temperature: 0.7})
      {:ok, "Why don't scientists trust atoms? Because they make up everything!"}
  """
  def complete(provider, prompt, options \\ %{}) do
    provider_module = get_provider_module(provider)
    provider_module.complete(prompt, options)
  end

  @doc """
  Generate a chat response using the specified LLM provider.

  ## Parameters
    * `provider` - The LLM provider to use (atom or module)
    * `messages` - The chat messages
    * `options` - Optional configuration for the provider

  ## Examples
      iex> messages = [
      ...>   %{role: "system", content: "You are a helpful assistant."},
      ...>   %{role: "user", content: "What is Elixir?"}
      ...> ]
      iex> Adk.LLM.chat(:openai, messages, %{temperature: 0.7})
      {:ok, %{role: "assistant", content: "Elixir is a functional, concurrent programming language..."}}
  """
  def chat(provider, messages, options \\ %{}) do
    provider_module = get_provider_module(provider)
    provider_module.chat(messages, options)
  end

  @doc """
  Get the configuration for a provider.

  ## Parameters
    * `provider` - The LLM provider (atom or module)

  ## Examples
      iex> Adk.LLM.config(:openai)
      %{name: "openai", api_key: "..."}
  """
  def config(provider) do
    provider_module = get_provider_module(provider)
    provider_module.config()
  end

  # Private functions

  defp get_provider_module(provider) when is_atom(provider) do
    case provider do
      :mock -> Adk.LLM.Providers.Mock
      :openai -> Adk.LLM.Providers.OpenAI
      :anthropic -> Adk.LLM.Providers.Anthropic
      module when is_atom(module) -> module
      _ -> raise ArgumentError, "Unknown LLM provider: #{inspect(provider)}"
    end
  end
end