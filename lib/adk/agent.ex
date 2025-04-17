defmodule Adk.Agent do
  @moduledoc """
  Behavior and utilities for implementing agents in the Adk framework.

  ## Extension Points

  - Implement the `run/2` callback for agent execution logic.
  - Optionally implement `handle_request/2` for custom request handling and decision routing.
  - Override `init/1` or `__initialize__/1` for custom initialization logic.
  - Override `handle_call/3` for advanced GenServer message handling.

  This module provides a clear separation between orchestration (agent lifecycle, state management) and LLM/tool invocation logic, which should be implemented in agent modules or delegated to other components.
  """

  @doc """
  Run the agent with the provided input.
  """
  @callback run(agent :: pid(), input :: any()) ::
              {:ok, map()} | {:error, {:run_failed, reason :: term()}}

  @doc """
  Handle a request and return a response. Override in custom agents for decision routing or workflow logic.
  """
  @callback handle_request(input :: any(), state :: any()) ::
              {:ok, map(), new_state :: any()} | {:error, reason :: term(), new_state :: any()}

  # We don't need this callback anymore as we use __initialize__ internally

  @doc """
  Run an agent with the given input.
  """
  def run(agent, input) when is_pid(agent) do
    GenServer.call(agent, {:run, input})
  end

  def run(agent_ref, input) when is_atom(agent_ref) or is_binary(agent_ref) do
    case Registry.lookup(Adk.AgentRegistry, agent_ref) do
      [{pid, _}] -> run(pid, input)
      [] -> {:error, {:agent_not_found, agent_ref}}
    end
  end

  @doc """
  Get the state of an agent.
  """
  def get_state(agent) when is_pid(agent) do
    GenServer.call(agent, :get_state)
  end

  def get_state(agent_ref) when is_atom(agent_ref) or is_binary(agent_ref) do
    case Registry.lookup(Adk.AgentRegistry, agent_ref) do
      [{pid, _}] -> get_state(pid)
      [] -> {:error, {:agent_not_found, agent_ref}}
    end
  end

  @doc """
  Macro to implement common agent functionality.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Adk.Agent
      use GenServer

      # Default implementation for Adk.Agent behaviour
      @impl Adk.Agent
      def run(agent, input), do: Adk.Agent.run(agent, input)

      # Default handle_request/2, can be overridden in custom agents
      @impl Adk.Agent
      def handle_request(input, state) do
        {:ok, %{output: "Agent handle_request not implemented"}, state}
      end

      # GenServer implementation
      @impl GenServer
      def init(config) do
        # Use internal __initialize__ to avoid conflicts
        case __initialize__(config) do
          {:ok, state} -> {:ok, state}
          {:error, reason} -> {:stop, reason}
        end
      end

      # Internal initialize function that can be overridden
      # without conflicting with GenServer.init
      defp __initialize__(config), do: {:ok, config}

      @impl GenServer
      def handle_call({:run, input}, _from, state) do
        # Delegate to handle_request/2 for custom agent logic
        case handle_request(input, state) do
          {:ok, response, new_state} -> {:reply, {:ok, response}, new_state}
          {:error, reason, new_state} -> {:reply, {:error, {:run_failed, reason}}, new_state}
        end
      end

      @impl GenServer
      def handle_call(:get_state, _from, state) do
        {:reply, {:ok, state}, state}
      end

      # Allow overriding default implementations
      defoverridable init: 1, run: 2, handle_call: 3, handle_request: 2
    end
  end
end
