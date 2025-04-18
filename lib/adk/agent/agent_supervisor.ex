defmodule Adk.Agent.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for managing agent processes in the ADK system.

  This supervisor is responsible for starting, supervising, and terminating agent processes dynamically at runtime. It uses a `:one_for_one` strategy, so if an agent process crashes, only that process is restarted.

  Agent can be registered with unique names via the `Adk.AgentRegistry`, allowing for lookup and communication by name.
  """
  use DynamicSupervisor

  @doc """
  Starts the AgentSupervisor process and links it to the current process.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  @doc """
  Initializes the DynamicSupervisor with a :one_for_one strategy.
  """
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
    agent_module = get_agent_module(agent_type)
    registry_name = Map.get(config, :name)

    # Define a full child spec map for DynamicSupervisor
    child_spec =
      if registry_name do
        %{
          id: registry_name,
          start:
            {agent_module, :start_link,
             [config, [name: {:via, Registry, {Adk.AgentRegistry, registry_name}}]]},
          restart: :permanent,
          type: :worker
        }
      else
        %{
          id: agent_module,
          start: {agent_module, :start_link, [config]},
          restart: :permanent,
          type: :worker
        }
      end

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Map agent type to its implementation module.
  """
  def get_agent_module(agent_type) do
    case agent_type do
      :sequential ->
        Adk.Agent.Sequential

      :parallel ->
        Adk.Agent.Parallel

      :loop ->
        Adk.Agent.Loop

      :llm ->
        Adk.Agent.LLM

      # Allow custom agent modules
      module when is_atom(module) ->
        if Code.ensure_loaded?(module) do
          module
        else
          {:error, {:agent_module_not_loaded, module}}
        end

      _ ->
        {:error, {:unknown_agent_type, agent_type}}
    end
  end
end
