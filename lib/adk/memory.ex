defmodule Adk.Memory do
  @moduledoc """
  Behavior and utilities for implementing memory services in the ADK framework.
  
  Memory services provide a way for agents to store and retrieve information across
  sessions or interactions.
  """
  
  @doc """
  Add a session to memory.
  
  ## Parameters
    * `session_id` - A unique identifier for the session
    * `data` - The data to store for the session
  """
  @callback add_session(session_id :: String.t(), data :: any()) :: :ok | {:error, term()}
  
  @doc """
  Search memory for sessions matching the query.
  
  ## Parameters
    * `session_id` - The session ID to search in (if applicable)
    * `query` - The search query (can be string or structured data)
  """
  @callback search(session_id :: String.t(), query :: any()) :: {:ok, [any()]} | {:error, term()}
  
  @doc """
  Get all sessions for the given ID.
  
  ## Parameters
    * `session_id` - The session ID to get data for
  """
  @callback get_sessions(session_id :: String.t()) :: {:ok, [any()]} | {:error, term()}
  
  @doc """
  Clear all sessions for the given ID.
  
  ## Parameters
    * `session_id` - The session ID to clear data for
  """
  @callback clear_sessions(session_id :: String.t()) :: :ok | {:error, term()}
  
  @doc """
  Add a session to memory using the configured service.
  
  ## Parameters
    * `service` - The memory service module or name
    * `session_id` - A unique identifier for the session
    * `data` - The data to store for the session
  """
  def add_session(service, session_id, data) do
    get_service_module(service).add_session(session_id, data)
  end
  
  @doc """
  Search memory for sessions matching the query using the configured service.
  
  ## Parameters
    * `service` - The memory service module or name
    * `session_id` - The session ID to search in (if applicable)
    * `query` - The search query (can be string or structured data)
  """
  def search(service, session_id, query) do
    get_service_module(service).search(session_id, query)
  end
  
  @doc """
  Get all sessions for the given ID using the configured service.
  
  ## Parameters
    * `service` - The memory service module or name
    * `session_id` - The session ID to get data for
  """
  def get_sessions(service, session_id) do
    get_service_module(service).get_sessions(session_id)
  end
  
  @doc """
  Clear all sessions for the given ID using the configured service.
  
  ## Parameters
    * `service` - The memory service module or name
    * `session_id` - The session ID to clear data for
  """
  def clear_sessions(service, session_id) do
    get_service_module(service).clear_sessions(session_id)
  end
  
  # Helper to get the memory service module
  defp get_service_module(service) when is_atom(service) do
    case service do
      :in_memory -> Adk.Memory.InMemory
      module when is_atom(module) -> module
      _ -> raise ArgumentError, "Unknown memory service: #{inspect(service)}"
    end
  end
  
  @doc """
  Macro to implement common memory service functionality.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Adk.Memory
      
      # Default implementations that can be overridden
      @impl Adk.Memory
      def add_session(session_id, data) do
        raise "Not implemented: add_session/2"
      end
      
      @impl Adk.Memory
      def search(session_id, query) do
        raise "Not implemented: search/2"
      end
      
      @impl Adk.Memory
      def get_sessions(session_id) do
        raise "Not implemented: get_sessions/1"
      end
      
      @impl Adk.Memory
      def clear_sessions(session_id) do
        raise "Not implemented: clear_sessions/1"
      end
      
      # Allow overriding default implementations
      defoverridable add_session: 2, search: 2, get_sessions: 1, clear_sessions: 1
    end
  end
end