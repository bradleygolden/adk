defmodule Adk.Agent do
  @moduledoc """
  Behavior and utilities for implementing agents in the ADK framework.
  """

  @doc """
  Run the agent with the provided input.
  """
  @callback run(agent :: pid(), input :: any()) :: {:ok, map()} | {:error, term()}

  # We don't need this callback anymore as we use __initialize__ internally

  @doc """
  Run an agent with the given input.
  """
  def run(agent, input) when is_pid(agent) do
    GenServer.call(agent, {:run, input})
  end

  def run(agent_ref, input) when is_atom(agent_ref) do
    case Registry.lookup(Adk.AgentRegistry, agent_ref) do
      [{pid, _}] -> run(pid, input)
      [] -> {:error, :agent_not_found}
    end
  end

  @doc """
  Get the state of an agent.
  """
  def get_state(agent) when is_pid(agent) do
    GenServer.call(agent, :get_state)
  end

  def get_state(agent_ref) when is_atom(agent_ref) do
    case Registry.lookup(Adk.AgentRegistry, agent_ref) do
      [{pid, _}] -> get_state(pid)
      [] -> {:error, :agent_not_found}
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
        # This would be overridden by the actual agent implementation
        {:reply, {:ok, %{output: "Agent not implemented"}}, state}
      end

      @impl GenServer
      def handle_call(:get_state, _from, state) do
        {:reply, {:ok, state}, state}
      end

      # Allow overriding default implementations
      defoverridable init: 1, run: 2, handle_call: 3
    end
  end
end
