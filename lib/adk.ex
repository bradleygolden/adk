defmodule Adk do
  @moduledoc """
  Adk - Agent Development Kit for Elixir

  A framework for building, running, and managing intelligent agents in Elixir.
  This module provides the primary API for interacting with the Adk framework.

  ## Core API

  - Agent creation and orchestration (sequential, parallel, loop, LLM, LangChain)
  - Tool registration and execution
  - Memory/session management
  - LLM provider integration (completion, chat)

  See the project documentation for detailed guides and examples.
  """

  @doc """
  Returns the current version of the Adk framework.
  """
  def version, do: "0.1.0"

  @doc """
  Initialize and start a new agent with the given configuration.

  ## Parameters
    * `agent_type` - The type of agent to create (e.g., :sequential, :parallel, :loop, :llm)
    * `config` - A map of configuration options for the agent.

  ## Examples
      iex> Adk.create_agent(:llm, %{name: "capital_agent", model: "gemini-flash", tools: [MyApp.Tools.GetCapital]})
      {:ok, agent_pid}
  """
  def create_agent(agent_type, config) do
    Adk.Agent.AgentSupervisor.start_agent(agent_type, config)
  end

  @doc """
  Run an agent with the given input.

  ## Parameters
    * `agent` - The agent pid or struct reference
    * `input` - The input to provide to the agent

  ## Examples
      iex> Adk.run(agent, "What is the weather today?")
      {:ok, %{output: "The weather is sunny."}}
  """
  def run(agent, input) do
    cond do
      # Handle PID case (GenServer/server-based agent)
      is_pid(agent) or is_atom(agent) or is_tuple(agent) ->
        Adk.Agent.Server.run(agent, input)

      # Handle struct case (direct call to implementation)
      is_map(agent) and is_atom(Map.get(agent, :__struct__)) ->
        Adk.Agent.run(agent, input)

      # Handle any other invalid cases
      true ->
        {:error,
         {:invalid_agent, "Agent must be a PID, registered name, or a valid agent struct"}}
    end
  end

  @doc """
  Register a new tool that can be used by agents.

  ## Parameters
    * `tool_module` - The module implementing the Adk.Tool behavior

  ## Examples
      iex> Adk.register_tool(MyApp.Tools.Weather)
      :ok
  """
  def register_tool(tool_module) do
    name =
      case tool_module.definition() do
        %{name: name} when is_binary(name) -> String.to_atom(name)
        %{name: name} when is_atom(name) -> name
        _ -> tool_module
      end

    Adk.ToolRegistry.register(name, tool_module)
    :ok
  end

  @doc """
  List all registered tools.

  ## Examples
      iex> Adk.list_tools()
      [MyApp.Tools.Weather, MyApp.Tools.Calculator]
  """
  def list_tools do
    Adk.ToolRegistry.list()
  end

  @doc """
  Execute a specific tool with parameters.

  ## Parameters
    * `tool_name` - The name of the tool to execute (atom)
    * `params` - The parameters to pass to the tool

  ## Examples
      iex> Adk.execute_tool(:calculator, %{"operation" => "add", "a" => 2, "b" => 3})
      {:ok, 5}
  """
  def execute_tool(tool_name, params) do
    context = %{session_id: "adk_facade_call", invocation_id: nil, tool_call_id: nil}
    Adk.ToolRegistry.execute_tool(tool_name, params, context)
  end

  @doc """
  Get a completion from an LLM provider.

  ## Parameters
    * `provider` - The LLM provider to use
    * `prompt` - The prompt to complete
    * `options` - Optional provider-specific options

  ## Examples
      iex> Adk.complete(:mock, "Tell me a joke")
      {:ok, "Why don't scientists trust atoms? Because they make up everything!"}
  """
  def complete(provider, prompt, options \\ %{}) do
    Adk.LLM.complete(provider, prompt, options)
  end

  @doc """
  Chat with an LLM provider.

  ## Parameters
    * `provider` - The LLM provider to use
    * `messages` - The chat messages
    * `options` - Optional provider-specific options

  ## Examples
      iex> messages = [
      ...>   %{role: "system", content: "You are a helpful assistant."},
      ...>   %{role: "user", content: "What's Elixir?"}
      ...> ]
      iex> Adk.chat(:mock, messages)
      {:ok, %{role: "assistant", content: "Elixir is a functional programming language..."}}
  """
  def chat(provider, messages, options \\ %{}) do
    Adk.LLM.chat(provider, messages, options)
  end

  # Memory-related functions

  @doc """
  Add a session to memory.

  ## Parameters
    * `service` - The memory service to use (:in_memory or a module)
    * `session_id` - A unique identifier for the session
    * `data` - The data to store

  ## Examples
      iex> Adk.add_to_memory(:in_memory, "user_123", "Important information to remember")
      :ok
  """
  def add_to_memory(service, session_id, data) do
    Adk.Memory.add_session(service, session_id, data)
  end

  @doc """
  Search memory for matching sessions.

  ## Parameters
    * `service` - The memory service to use (:in_memory or a module)
    * `session_id` - The session ID to search in
    * `query` - The search query (string, regex, or map)

  ## Examples
      iex> Adk.search_memory(:in_memory, "user_123", "important")
      {:ok, ["Important information to remember"]}
  """
  def search_memory(service, session_id, query) do
    Adk.Memory.search(service, session_id, query)
  end

  @doc """
  Get all sessions for an ID.

  ## Parameters
    * `service` - The memory service to use (:in_memory or a module)
    * `session_id` - The session ID to get data for

  ## Examples
      iex> Adk.get_memory(:in_memory, "user_123")
      {:ok, ["Important information to remember", "Another piece of information"]}
  """
  def get_memory(service, session_id) do
    Adk.Memory.get_sessions(service, session_id)
  end

  @doc """
  Clear all sessions for an ID.

  ## Parameters
    * `service` - The memory service to use (:in_memory or a module)
    * `session_id` - The session ID to clear

  ## Examples
      iex> Adk.clear_memory(:in_memory, "user_123")
      :ok
  """
  def clear_memory(service, session_id) do
    Adk.Memory.clear_sessions(service, session_id)
  end
end
