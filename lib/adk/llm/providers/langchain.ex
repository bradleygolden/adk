defmodule Adk.LLM.Providers.Langchain do
  @moduledoc """
  Handles interaction with Langchain API for LLM tasks.
  """
  require Logger
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
          case get_langchain_model(
                 model,
                 Map.merge(options, %{temperature: temperature, max_tokens: max_tokens})
               ) do
            {:ok, llm} ->
              # Create a simple chain with just the prompt - try both formats
              try do
                # First try map format (newer versions)
                chain = apply(LangChain.Chains.LLMChain, :new!, [%{prompt: prompt, llm: llm}])
                # Empty keyword list instead of map
                apply(LangChain.Chains.LLMChain, :run, [chain, []])
              rescue
                # Fall back to keyword list format (older versions)
                _ ->
                  chain = apply(LangChain.Chains.LLMChain, :new!, [[prompt: prompt, llm: llm]])
                  # Empty keyword list instead of map
                  apply(LangChain.Chains.LLMChain, :run, [chain, []])
              end

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
        tool_names = Map.get(options, :tools, [])

        # Fetch and format available tools based on the names provided
        # Use lookup/1 and handle potential errors
        {tool_modules, errors} =
          Enum.map(tool_names, &Adk.ToolRegistry.lookup/1)
          |> Enum.split_with(&match?({:ok, _}, &1))

        if !Enum.empty?(errors) do
          Logger.warning("Could not find some tools for Langchain agent: #{inspect(errors)}")
        end

        formatted_tools =
          format_tools_for_openai(tool_modules |> Enum.map(fn {:ok, mod} -> mod end))

        # Convert messages to LangChain format
        langchain_messages = Enum.map(messages, &convert_message_to_langchain/1)

        # Merge tools into options for model creation
        model_options =
          Map.merge(options, %{
            temperature: temperature,
            max_tokens: max_tokens,
            # Pass formatted tools if any exist
            tools: formatted_tools |> Enum.filter(&(!is_nil(&1)))
          })

        case get_langchain_model(model, model_options) do
          {:ok, llm} ->
            try do
              # Revert to using LLMChain.run
              run_result =
                LangChain.Chains.LLMChain.new!(%{llm: llm})
                |> LangChain.Chains.LLMChain.add_messages(langchain_messages)
                |> LangChain.Chains.LLMChain.run()

              case run_result do
                {:ok, updated_chain} ->
                  case updated_chain.messages |> List.last() do
                    nil ->
                      {:error, "No response message found in LangChain chain messages"}

                    %{role: :assistant, content: content, tool_calls: tool_calls} ->
                      {:ok, %{content: content, tool_calls: tool_calls}}

                    # No tool calls
                    %{role: :assistant, content: content} ->
                      {:ok, %{content: content, tool_calls: nil}}

                    # Handle the unexpected structure seen in logs
                    %{message: %{"content" => content, "role" => "assistant"}} ->
                      Logger.warning(
                        "Handling slightly unexpected message format: #{inspect(content)}"
                      )

                      {:ok, %{content: content, tool_calls: nil}}

                    other_message ->
                      Logger.warning(
                        "Unexpected last message format from LangChain: #{inspect(other_message)}"
                      )

                      content = Map.get(other_message, :content)
                      tool_calls = Map.get(other_message, :tool_calls)
                      {:ok, %{content: content, tool_calls: tool_calls}}
                  end

                # Handle the specific error case seen in logs directly
                {:ok, [error: %LangChain.LangChainError{message: "Unexpected response"} = err]} ->
                  Logger.error(
                    "LLMChain run returned an unexpected response error block: #{inspect(err)}"
                  )

                  {:error, {:llm_provider_error, "LLMChain run returned unexpected error block"}}

                # Handle potential error formats from LLMChain.run
                # 3-tuple error
                {:error, _chain_state, reason} ->
                  {:error, reason}

                # 2-tuple error
                {:error, reason} ->
                  {:error, reason}

                # Catch other cases
                other ->
                  {:error, "Unexpected result from LLMChain.run: #{inspect(other)}"}
              end
            rescue
              e -> {:error, "Failed to run LLMChain: #{inspect(e)}"}
            end

          # Error from get_langchain_model
          {:error, reason} ->
            {:error, reason}
        end

      # Error from ensure_langchain_available
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

  # Utility functions (public for testing)

  def ensure_langchain_available do
    # Multi-step approach to reliably detect if LangChain is available

    # Step 1: Check if LangChain is available in the application environment
    langchain_app =
      try do
        Application.get_application(LangChain)
      rescue
        _ -> nil
      end

    # Step 2: If LangChain app is detected, make sure the module actually exists
    if is_atom(langchain_app) do
      if Code.ensure_loaded?(LangChain) do
        # Everything is good - LangChain is available and loaded
        :ok
      else
        # Strange state - app is loaded but module isn't
        try_load_langchain()
      end
    else
      # Step 3: App not available, so try alternatives
      try_load_langchain()
    end
  end

  # Private helper to try multiple approaches to load LangChain
  defp try_load_langchain do
    try do
      # Check if the module is available but not loaded
      if Code.ensure_loaded?(LangChain) do
        # Module loaded successfully
        :ok
      else
        # Try to find LangChain in the load path
        path = :code.which(LangChain)

        case path do
          # LangChain is available in path
          path when is_list(path) ->
            # Try to dynamically load it
            try do
              {:module, _} = Code.ensure_compiled(LangChain)
              :ok
            rescue
              _ ->
                {:error,
                 "LangChain is in the path but could not be compiled. Version may be incompatible."}
            end

          # Try looking for LangChain.Message as an alternative indicator
          :non_existing ->
            # Check for LangChain.Message which is a key component
            if Code.ensure_loaded?(LangChain.Message) do
              :ok
            else
              path = :code.which(LangChain.Message)

              case path do
                path when is_list(path) ->
                  :ok

                :non_existing ->
                  {:error, "LangChain library is not available. Add it to your dependencies."}
              end
            end
        end
      end
    rescue
      e ->
        # Capture the specific error for debugging
        error_msg = Exception.message(e)

        {:error,
         "Error loading LangChain: #{error_msg}. Make sure the dependency is properly configured."}
    end
  end

  # Helper to format ADK tool definitions for OpenAI
  defp format_tools_for_openai(tool_modules) do
    Enum.map(tool_modules, fn module ->
      try do
        definition = module.definition()

        %{
          type: "function",
          function: %{
            name: definition.name,
            description: definition.description,
            # Assuming definition.parameters is already a JSON Schema map
            parameters: definition.parameters
          }
        }
      rescue
        # Handle potential errors during definition fetching
        _ -> nil
      end
    end)
  end

  def get_langchain_model(model, options) do
    try do
      # Get provider from options or default to :openai
      provider = Map.get(options, :provider, :openai)

      # Get API URL from options if provided
      api_url = Map.get(options, :endpoint)

      # Get API key from options or application config
      api_key = get_api_key(provider, options)

      # Create base config
      config = %{
        model: model,
        temperature: Map.get(options, :temperature, 0.7),
        max_tokens: Map.get(options, :max_tokens, 1000)
      }

      # Add API key to config if provided
      config = if api_key, do: Map.put(config, :api_key, api_key), else: config

      # Add API URL to config if provided
      config = if api_url, do: Map.put(config, :endpoint, api_url), else: config

      # Add tools to config if present in options (specifically for OpenAI)
      config =
        if provider == :openai && Map.has_key?(options, :tools) do
          Map.put(config, :tools, Map.get(options, :tools))
        else
          config
        end

      # Create the model based on provider
      case provider do
        :openai ->
          {:ok, apply(LangChain.ChatModels.ChatOpenAI, :new!, [config])}

        :anthropic ->
          # Note: Anthropic tool support might differ, not handled here
          {:ok, apply(LangChain.ChatModels.ChatAnthropic, :new!, [config])}

        _ ->
          {:error, "Unsupported provider: #{provider}"}
      end
    rescue
      e ->
        {:error, "Failed to create LangChain model: #{inspect(e)}"}
    end
  end

  # Helper function to get API key based on provider
  defp get_api_key(provider, options) do
    # First try to get from options
    api_key = Map.get(options, :api_key)
    if api_key, do: api_key, else: get_api_key_from_config(provider)
  end

  defp get_api_key_from_config(:openai) do
    Application.get_env(:langchain, :openai_key)
  end

  defp get_api_key_from_config(:anthropic) do
    Application.get_env(:langchain, :anthropic_key)
  end

  defp get_api_key_from_config(_), do: nil

  def convert_message_to_langchain(%{role: role, content: content}) do
    # Map ADK message roles to LangChain roles with more robust handling
    role_atom =
      case role do
        "system" ->
          :system

        "user" ->
          :user

        "assistant" ->
          :assistant

        "function" ->
          :tool

        "tool" ->
          :tool

        string when is_binary(string) ->
          try do
            String.to_atom(string)
          rescue
            # Default to user if conversion fails
            _ -> :user
          end

        atom when is_atom(atom) ->
          atom

        # Default to user for any other type
        _ ->
          :user
      end

    try do
      # Use the LangChain.Message dedicated constructors based on role
      # This is the recommended way to create messages in LangChain
      case role_atom do
        :system ->
          apply(LangChain.Message, :new_system!, [content])

        :user ->
          apply(LangChain.Message, :new_user!, [content])

        :assistant ->
          apply(LangChain.Message, :new_assistant!, [content])

        :tool ->
          # For tool messages we need the special tool_result constructor
          apply(LangChain.Message, :new_tool_result!, [%{content: content}])

        _ ->
          # For any other role, use the generic constructor
          apply(LangChain.Message, :new!, [%{role: role_atom, content: content}])
      end
    rescue
      _e ->
        # If the message-specific constructors fail, try with generic constructors
        try do
          # Try LangChain.Message.new!/2 first
          if function_exported?(LangChain.Message, :new!, 2) do
            apply(LangChain.Message, :new!, [role_atom, content])
            # Then try with map format
          else
            apply(LangChain.Message, :new!, [%{role: role_atom, content: content}])
          end
        rescue
          # If all else fails, create a compatible map/struct
          _ -> create_message_fallback(role_atom, content)
        end
    end
  end

  # Fallback for when all message creation methods fail
  defp create_message_fallback(role, content) do
    # Try to create a struct if LangChain.Message is available
    if Code.ensure_loaded?(LangChain.Message) do
      try do
        struct(LangChain.Message, role: role, content: content)
      rescue
        # Last resort: a map with the correct format
        _ -> %{role: role, content: content}
      end
    else
      # Format the map based on role for compatibility
      case role do
        :system -> %{role: :system, content: content}
        :user -> %{role: :user, content: content}
        :assistant -> %{role: :assistant, content: content}
        :tool -> %{role: :tool, content: content, name: "function"}
        _ -> %{role: role, content: content}
      end
    end
  end
end
