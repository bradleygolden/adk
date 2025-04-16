defmodule Adk.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for dynamically created agents
      {Registry, keys: :unique, name: Adk.AgentRegistry},
      # Registry for tools
      {Registry, keys: :unique, name: Adk.ToolRegistry.Registry},
      # Supervisor for managing agent processes
      Adk.AgentSupervisor,
      # Tool registry service (Now just a module, Registry started above)
      # In-memory memory service
      Adk.Memory.InMemory
    ]

    opts = [strategy: :one_for_one, name: Adk.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
