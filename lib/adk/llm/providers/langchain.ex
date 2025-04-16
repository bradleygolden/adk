defmodule Adk.LLM.Providers.Langchain do
  @moduledoc """
  A provider that integrates with Elixir's LangChain library.
  """
  use Adk.LLM.Provider

  @impl true
  def complete(prompt, options) do
    case ensure_langchain_available() do
      :ok ->
        # Extract model name or use default
        model = Map.get(options, :model, "gpt-3.5-turbo")
        # Extract other options
        temperature = Map.get(options, :temperature, 0.7)
        max_tokens = Map.get(options, :max_tokens, 1000)
        
        # Create a langchain model
        llm_result = 
          case get_langchain_model(model, Map.merge(options, %{temperature: temperature, max_tokens: max_tokens})) do
            {:ok, llm} ->
              # Create a simple chain with just the prompt
              chain = apply(LangChain.Chains.LLMChain, :new!, [[prompt: prompt, llm: llm]])
              apply(LangChain.Chains.LLMChain, :run, [chain, %{}])
            
            {:error, reason} ->
              {:error, reason}
          end
        
        case llm_result do
          {:ok, %{text: text}} -> {:ok, text}
          {:error, reason} -> {:error, reason}
          other -> {:error, "Unexpected response: #{inspect(other)}"}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def chat(messages, options) do
    case ensure_langchain_available() do
      :ok ->
        # Extract model name or use default
        model = Map.get(options, :model, "gpt-3.5-turbo")
        # Extract other options
        temperature = Map.get(options, :temperature, 0.7)
        max_tokens = Map.get(options, :max_tokens, 1000)
        
        # Convert messages to LangChain format
        langchain_messages = Enum.map(messages, &convert_message_to_langchain/1)
        
        # Create a langchain model
        llm_result = 
          case get_langchain_model(model, Map.merge(options, %{temperature: temperature, max_tokens: max_tokens})) do
            {:ok, llm} ->
              # Use the chat model directly
              apply(LangChain.ChatModels.ChatModel, :call_chat, [llm, langchain_messages])
            
            {:error, reason} ->
              {:error, reason}
          end
        
        case llm_result do
          {:ok, response} -> 
            # Convert LangChain message back to ADK format
            {:ok, %{role: "assistant", content: response.content}}
          {:error, reason} -> 
            {:error, reason}
          other -> 
            {:error, "Unexpected response: #{inspect(other)}"}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def config do
    %{
      name: "langchain",
      description: "Adapter for Elixir LangChain"
    }
  end

  # Private helpers

  def ensure_langchain_available do
    cond do
      Code.ensure_loaded?(LangChain) -> :ok
      true -> {:error, "LangChain library is not available. Add it to your dependencies."}
    end
  end

  defp get_langchain_model(model_name, options) do
    # Initialize the appropriate model based on the name and provider
    provider = Map.get(options, :provider, :openai)

    case provider do
      :openai ->
        {:ok, apply(LangChain.ChatModels.ChatOpenAI, :new!, [[model: model_name, temperature: options.temperature]])}
      
      :anthropic ->
        {:ok, apply(LangChain.ChatModels.ChatAnthropic, :new!, [[model: model_name, temperature: options.temperature]])}
      
      :google ->
        {:ok, apply(LangChain.ChatModels.ChatGoogleAI, :new!, [[model: model_name, temperature: options.temperature]])}
      
      :ollama ->
        {:ok, apply(LangChain.ChatModels.ChatOllama, :new!, [[model: model_name, temperature: options.temperature]])}
      
      :mistral ->
        {:ok, apply(LangChain.ChatModels.ChatMistral, :new!, [[model: model_name, temperature: options.temperature]])}
      
      _other ->
        {:error, "Unsupported LangChain provider: #{inspect(provider)}"}
    end
  rescue
    e -> {:error, "Failed to initialize LangChain model: #{inspect(e)}"}
  end

  def convert_message_to_langchain(%{role: role, content: content}) do
    # Map ADK message roles to LangChain roles
    role = case role do
      "system" -> :system
      "user" -> :user
      "assistant" -> :assistant
      "function" -> :tool
      other -> String.to_atom(other)
    end

    apply(LangChain.Message, :new, [role, content])
  end
end