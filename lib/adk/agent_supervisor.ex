defmodule Adk.AgentSupervisor do
  @moduledoc """
  Supervisor for managing agent processes.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new agent process of the specified type with the given configuration.

  ## Parameters
    * `agent_type` - The type of agent to create (:sequential, :parallel, :loop, :llm)
    * `config` - Configuration map for the agent

  ## Returns
    * `{:ok, pid}` - The process ID of the new agent
    * `{:error, reason}` - Error information if the agent couldn't be started
  """
  def start_agent(agent_type, config) do
    # Get the appropriate module based on agent type
    agent_module = get_agent_module(agent_type)

    # Set the agent name if provided
    registry_name = Map.get(config, :name)

    # Define the child spec for the agent
    child_spec = if registry_name do
      {agent_module, {config, [name: {:via, Registry, {Adk.AgentRegistry, registry_name}}]}}
    else
      {agent_module, config}
    end

    # Start the agent under the supervisor
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Map agent type to its implementation module.
  """
  def get_agent_module(agent_type) do
    case agent_type do
      :sequential -> Adk.Agents.Sequential
      :parallel -> Adk.Agents.Parallel
      :loop -> Adk.Agents.Loop
      :llm -> Adk.Agents.LLM
      :langchain -> Adk.Agents.Langchain
      module when is_atom(module) -> module  # Allow custom agent modules
      _ -> raise ArgumentError, "Unknown agent type: #{inspect(agent_type)}"
    end
  end
end