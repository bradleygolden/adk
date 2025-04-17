defmodule Adk.Application do
  @moduledoc """
  OTP Application entrypoint for the Adk framework.

  ## Supervision Tree

  - `Registry` (Adk.AgentRegistry): Tracks dynamically created agent processes by name.
  - `Adk.ToolRegistry.Server`: Owns the ETS table for tool registration and lookup.
  - `Adk.AgentSupervisor`: Supervises agent processes (one_for_one strategy).
  - `Adk.Memory.InMemory`: In-memory memory provider for agent state and event storage.

  ## Configuration Keys

  - `:adk, :llm_provider` – Default LLM provider (e.g., `:mock`, `:langchain`).
  - `:adk, :tool_registry` – Tool registry backend (default: ETS).
  - `:adk, :memory_provider` – Memory backend (default: in-memory).
  - `:langchain, :openai_key` – API key for OpenAI provider (if using LangChain).
  - `:langchain, :anthropic_key` – API key for Anthropic provider (if using LangChain).

  ## Telemetry & Events

  Telemetry hooks for key operations (tool registry changes, LLM calls, etc.) should be attached in the relevant modules (e.g., `Adk.ToolRegistry`, `Adk.LLM`).
  This application module does not attach telemetry handlers directly.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for dynamically created agents
      {Registry, keys: :unique, name: Adk.AgentRegistry},
      # Tool registry ETS owner
      Adk.ToolRegistry.Server,
      # Supervisor for managing agent processes
      Adk.AgentSupervisor,
      # In-memory memory service
      Adk.Memory.InMemory
    ]

    opts = [strategy: :one_for_one, name: Adk.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
