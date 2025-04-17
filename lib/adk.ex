defmodule Adk do
  @moduledoc """
  Adk - Agent Development Kit for Elixir

  A framework for building, running, and managing intelligent agents in Elixir.
  This module provides the primary API for interacting with the Adk framework.
  """

  @doc """
  Returns the current version of the Adk framework.
  """
  def version, do: "0.1.0"

  @doc """
  Initialize and start a new agent with the given configuration.

  ## Parameters
    * `agent_type` - The type of agent to create (e.g., :sequential, :parallel, :loop, :llm)
    * `config` - A map of configuration options for the agent. Common options include:
      * `:name` (atom or string) - A unique name for the agent.
      * `:description` (string) - A description of the agent's capabilities (used by other agents).
      * `:tools` (list) - A list of tool modules or functions the agent can use.
      * `:instruction` (string) - Instructions guiding the agent's behavior.
      * `:model` (string or atom) - The underlying LLM model identifier (for LLM agents).
      * `:input_schema` (module) - Optional. An Elixir struct module defining the expected input structure. Input must be a JSON string conforming to this schema.
      * `:output_schema` (module) - Optional. An Elixir struct module defining the desired output structure. The agent will attempt to generate a JSON string conforming to this schema. **Using this option disables tool usage for the agent.**
      * `:output_key` (atom or string) - Optional. If set, the agent's final response content will be stored in the session state under this key.
      * ... (other agent-type specific options)

  ## Examples
      iex> Adk.create_agent(:llm, %{name: "capital_agent", model: "gemini-flash", tools: [MyApp.Tools.GetCapital]})
      {:ok, agent_pid}

      iex> defmodule CapitalInput do
      ...>   @enforce_keys [:country]
      ...>   defstruct [:country]
      ...> end
      iex> defmodule CapitalOutput do
      ...>   @enforce_keys [:capital]
      ...>   defstruct [:capital]
      ...> end
      iex> Adk.create_agent(:llm, %{
      ...>   name: "structured_capital_agent",
      ...>   model: "gemini-flash",
      ...>   instruction: "Given a country in JSON like `{"country": "France"}`, respond ONLY with JSON like `{"capital": "Paris"}`.",
      ...>   input_schema: CapitalInput,
      ...>   output_schema: CapitalOutput,
      ...>   output_key: :capital_result
      ...> })
      {:ok, agent_pid}
  """
  def create_agent(agent_type, config) do
    Adk.AgentSupervisor.start_agent(agent_type, config)
  end

  @doc """
  Run an agent with the given input.

  ## Parameters
    * `agent` - The agent pid or reference
    * `input` - The input to provide to the agent

  ## Examples
      iex> Adk.run(agent, "What is the weather today?")
      {:ok, %{output: "The weather is sunny."}}
  """
  def run(agent, input) do
    Adk.Agent.run(agent, input)
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
    # Register under the tool's definition name (as atom)
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
  Get an agent's current state.

  ## Parameters
    * `agent` - The agent pid or reference

  ## Examples
      iex> Adk.get_state(agent)
      {:ok, %{name: "my_agent", memory: %{}, ...}}
  """
  def get_state(agent) do
    Adk.Agent.get_state(agent)
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
    # Create a minimal context map. If session/invocation info is needed here,
    # this function signature would need to change.
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

  # Agent-to-agent communication

  @doc """
  Call another agent within the same system.

  ## Parameters
    * `agent` - The agent to call (pid or name)
    * `input` - The input to provide to the agent
    * `metadata` - Optional metadata about the call

  ## Examples
      iex> Adk.call_agent(weather_agent, "What's the weather in New York?")
      {:ok, %{output: "It's sunny in New York."}}
  """
  def call_agent(agent, input, metadata \\ %{}) do
    Adk.A2A.call_local(agent, input, metadata)
  end

  @doc """
  Call a remote agent via HTTP.

  ## Parameters
    * `url` - The URL of the remote agent's /run endpoint
    * `input` - The input to provide to the agent
    * `metadata` - Optional metadata to send with the request
    * `options` - Additional HTTP request options

  ## Examples
      iex> Adk.call_remote_agent("https://weather-agent.example.com/run", "What's the weather in New York?")
      {:ok, %{output: "It's sunny in New York.", metadata: %{agent_name: "weather"}}}
  """
  def call_remote_agent(url, input, metadata \\ %{}, options \\ []) do
    Adk.A2A.call_remote(url, input, metadata, options)
  end

  @doc """
  Make an agent available via HTTP.

  ## Parameters
    * `agent` - The agent to expose (pid or name)
    * `path` - The path to make the agent available at

  ## Examples
      iex> Adk.expose_agent(weather_agent, "/agents/weather")
      :ok
  """
  def expose_agent(agent, path \\ "/run") do
    Adk.A2A.register_http(agent, path)
  end
end
