defmodule Adk.Memory.InMemory do
  @moduledoc """
  A simple in-memory implementation of the Memory service.
  
  This module stores session data in an Agent process, making it suitable for
  development and testing, but not for production use as data will be lost when
  the application restarts.
  """
  use Adk.Memory
  use Agent
  
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end
  
  @impl Adk.Memory
  def add_session(session_id, data) do
    Agent.update(__MODULE__, fn state ->
      # Get existing sessions for this ID or initialize empty list
      sessions = Map.get(state, session_id, [])
      # Add the new data to the sessions list
      updated_sessions = [data | sessions]
      # Update the state with the new sessions list
      Map.put(state, session_id, updated_sessions)
    end)
    
    :ok
  end
  
  @impl Adk.Memory
  def search(session_id, query) when is_binary(query) do
    # Simple keyword search implementation
    sessions = Agent.get(__MODULE__, &Map.get(&1, session_id, []))
    
    results = Enum.filter(sessions, fn session ->
      case session do
        str when is_binary(str) -> String.contains?(str, query)
        map when is_map(map) -> map_contains_query?(map, query)
        _ -> false
      end
    end)
    
    {:ok, results}
  end
  
  @impl Adk.Memory
  def search(session_id, regex) when is_struct(regex, Regex) do
    # Regex search implementation
    sessions = Agent.get(__MODULE__, &Map.get(&1, session_id, []))
    
    results = Enum.filter(sessions, fn session ->
      case session do
        str when is_binary(str) -> Regex.match?(regex, str)
        map when is_map(map) -> map_matches_regex?(map, regex)
        _ -> false
      end
    end)
    
    {:ok, results}
  end
  
  @impl Adk.Memory
  def search(session_id, %{} = query_map) do
    # Map/object search implementation
    sessions = Agent.get(__MODULE__, &Map.get(&1, session_id, []))
    
    results = Enum.filter(sessions, fn session ->
      case session do
        %{} = map -> map_matches_submap?(map, query_map)
        _ -> false
      end
    end)
    
    {:ok, results}
  end
  
  @impl Adk.Memory
  def get_sessions(session_id) do
    sessions = Agent.get(__MODULE__, &Map.get(&1, session_id, []))
    {:ok, sessions}
  end
  
  @impl Adk.Memory
  def clear_sessions(session_id) do
    Agent.update(__MODULE__, &Map.delete(&1, session_id))
    :ok
  end
  
  # Private helper functions
  
  defp map_contains_query?(map, query) when is_map(map) and is_binary(query) do
    Enum.any?(map, fn {_k, v} ->
      cond do
        is_binary(v) -> String.contains?(v, query)
        is_map(v) -> map_contains_query?(v, query)
        true -> false
      end
    end)
  end
  
  defp map_matches_regex?(map, regex) when is_map(map) and is_struct(regex, Regex) do
    Enum.any?(map, fn {_k, v} ->
      cond do
        is_binary(v) -> Regex.match?(regex, v)
        is_map(v) -> map_matches_regex?(v, regex)
        true -> false
      end
    end)
  end
  
  defp map_matches_submap?(map, submap) when is_map(map) and is_map(submap) do
    Enum.all?(submap, fn {k, v} ->
      case Map.get(map, k) do
        nil -> false
        ^v -> true
        map_v when is_map(map_v) and is_map(v) -> map_matches_submap?(map_v, v)
        _ -> false
      end
    end)
  end
end