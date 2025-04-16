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
    with {:ok, provider_module} <- get_provider_module(provider) do
      provider_module.complete(prompt, options)
    else
      # Propagate the error tuple
      {:error, reason} -> {:error, reason}
    end
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
    with {:ok, provider_module} <- get_provider_module(provider) do
      provider_module.chat(messages, options)
    else
      # Propagate the error tuple
      {:error, reason} -> {:error, reason}
    end
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
    with {:ok, provider_module} <- get_provider_module(provider) do
      provider_module.config()
    else
      # Propagate the error tuple
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp get_provider_module(provider) when is_atom(provider) do
    # TODO: Add Langchain provider mapping
    case provider do
      :mock ->
        {:ok, Adk.LLM.Providers.Mock}

      # Added Langchain
      :langchain ->
        {:ok, Adk.LLM.Providers.Langchain}

      # :openai -> {:ok, Adk.LLM.Providers.OpenAI} # Assuming these might exist later
      # :anthropic -> {:ok, Adk.LLM.Providers.Anthropic}
      module when is_atom(module) ->
        # Assume any other atom is a potential module. Validation happens at call time.
        {:ok, module}

      _ ->
        {:error, {:unknown_provider, provider}}
    end
  end

  # Handle cases where a non-atom is passed
  defp get_provider_module(provider) do
    {:error, {:invalid_provider_type, provider}}
  end
end
