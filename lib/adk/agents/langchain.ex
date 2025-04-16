defmodule Adk.Agents.Langchain do
  @moduledoc """
  An agent that uses LangChain Elixir for reasoning and tool handling.

  This agent integrates with the LangChain Elixir library, allowing you to use
  LangChain's features while maintaining ADK's agent interface.
  """
  use GenServer
  @behaviour Adk.Agent
  
  @impl Adk.Agent
  def run(agent, input), do: Adk.Agent.run(agent, input)

  @impl GenServer
  def init(config) do
    # Validate required config and LangChain availability
    case validate_config(config) do
      :ok ->
        # Initialize state
        state = %{
          name: Map.get(config, :name),
          tools: Map.get(config, :tools, []),
          llm_provider: Map.get(config, :llm_provider, :langchain),
          llm_options: Map.get(config, :llm_options, %{}),
          system_prompt: Map.get(config, :system_prompt, default_system_prompt()),
          memory: %{messages: []},
          config: config
        }

        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl GenServer
  def handle_call({:run, input}, _from, state) do
    # Process the user input using LangChain
    new_state = add_message(state, "user", input)

    case process_with_langchain(new_state) do
      {:ok, response, final_state} ->
        # Return the response and updated state
        {:reply, {:ok, %{output: response}}, final_state}

      {:error, reason, final_state} ->
        {:reply, {:error, reason}, final_state}
    end
  end

  # Functions that may be called from tests
  # They're public for testing but not part of the public API
  
  def validate_config(config) do
    cond do
      !is_map(config) ->
        {:error, "Config must be a map"}

      !Code.ensure_loaded?(LangChain) ->
        {:error, "LangChain library is not available. Add it to your dependencies."}

      true ->
        :ok
    end
  end

  def process_with_langchain(state) do
    try do
      # Get available tools
      available_tools = get_available_tools(state.tools)
      
      # Convert ADK tools to LangChain tools
      langchain_tools = convert_to_langchain_tools(available_tools)
      
      # Prepare messages
      langchain_messages = prepare_langchain_messages(state)
      
      # Get LLM from provider (default to OpenAI)
      provider = Map.get(state.llm_options, :provider, :openai)
      model = Map.get(state.llm_options, :model, "gpt-3.5-turbo")
      temperature = Map.get(state.llm_options, :temperature, 0.7)
      
      # Create LangChain chain with tools
      result = 
        case create_langchain_agent(provider, model, temperature, langchain_tools, langchain_messages) do
          {:ok, agent} ->
            # Run the chain
            apply(LangChain.Chains.LLMChain, :run, [agent, %{}])
            
          {:error, reason} ->
            {:error, reason}
        end
      
      # Process result
      case result do
        {:ok, %{text: response}} ->
          # Add agent's response to memory
          new_state = add_message(state, "assistant", response)
          {:ok, response, new_state}
        
        {:error, reason} ->
          {:error, reason, state}
        
        other ->
          {:error, "Unexpected result: #{inspect(other)}", state}
      end
    rescue
      e ->
        {:error, "LangChain error: #{inspect(e)}", state}
    end
  end
  
  defp create_langchain_agent(provider, model, temperature, tools, messages) do
    try do
      # Create LLM
      llm = case provider do
        :openai ->
          apply(LangChain.ChatModels.ChatOpenAI, :new!, [[model: model, temperature: temperature]])
        
        :anthropic ->
          apply(LangChain.ChatModels.ChatAnthropic, :new!, [[model: model, temperature: temperature]])
        
        :google ->
          apply(LangChain.ChatModels.ChatGoogleAI, :new!, [[model: model, temperature: temperature]])
        
        _other ->
          apply(LangChain.ChatModels.ChatOpenAI, :new!, [[model: model, temperature: temperature]])
      end
      
      # Create agent chain with tools
      chain = apply(LangChain, :agent, [
        [
          llm: llm,
          tools: tools,
          # We use the messages directly with a simple conversion
          system_message: get_system_message(messages)
        ]
      ])
      
      {:ok, chain}
    rescue
      e -> {:error, "Failed to create LangChain agent: #{inspect(e)}"}
    end
  end
  
  defp get_system_message(messages) do
    # Find the system message
    system_message = Enum.find(messages, fn msg -> 
      case msg do
        %{role: :system} -> true
        _ -> false
      end
    end)
    
    case system_message do
      %{content: content} -> content
      _ -> default_system_prompt()
    end
  end
  
  defp convert_to_langchain_tools(adk_tools) do
    Enum.map(adk_tools, fn tool_module ->
      definition = tool_module.definition()
      
      # Create a LangChain tool that will call our ADK tool
      # Each tool is a map with :name, :description, and :function keys
      %{
        name: definition.name,
        description: definition.description,
        function: fn args ->
          case tool_module.execute(args) do
            {:ok, result} -> result
            {:error, reason} -> "Error: #{inspect(reason)}"
          end
        end
      }
    end)
  end
  
  def get_available_tools(tool_names) do
    # Get all registered tools
    all_tools = Adk.list_tools()

    # Filter to just the requested tools if provided
    if is_list(tool_names) && !Enum.empty?(tool_names) do
      tool_names
      |> Enum.map(&String.to_atom/1)
      |> Enum.filter(fn name ->
        Enum.any?(all_tools, fn module ->
          module.definition().name == Atom.to_string(name)
        end)
      end)
      |> Enum.map(fn name ->
        Enum.find(all_tools, fn module ->
          module.definition().name == Atom.to_string(name)
        end)
      end)
    else
      all_tools
    end
  end

  defp prepare_langchain_messages(state) do
    # Convert ADK messages to LangChain messages
    [%{role: "system", content: state.system_prompt} | state.memory.messages]
    |> Enum.map(fn message ->
      role = case message.role do
        "system" -> :system
        "user" -> :user
        "assistant" -> :assistant
        "function" -> :tool
        other -> String.to_atom(other)
      end
      
      apply(LangChain.Message, :new, [role, message.content])
    end)
  end

  def add_message(state, role, content, metadata \\ %{}) do
    # Create the new message
    new_message = Map.merge(%{role: role, content: content}, metadata)

    # Add it to the state
    updated_messages = state.memory.messages ++ [new_message]
    updated_memory = Map.put(state.memory, :messages, updated_messages)

    # Update state
    %{state | memory: updated_memory}
  end

  defp default_system_prompt do
    """
    You are a helpful AI assistant. You have access to a set of tools that you can use to answer the user's questions.
    Use the tools available to you to help the user with their questions.
    """
  end

  def start_link({config, opts}) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  def start_link(config) when is_map(config) do
    GenServer.start_link(__MODULE__, config, [])
  end
end