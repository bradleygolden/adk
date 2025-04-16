defmodule Adk.Tools.MemoryTool do
  @moduledoc """
  A tool for agents to interact with the memory service.
  """
  use Adk.Tool
  
  @impl Adk.Tool
  def definition do
    %{
      name: "memory_tool",
      description: "Allows agents to store and retrieve information from long-term memory",
      parameters: %{
        action: %{
          type: "string",
          description: "The action to perform: save, search, get, or clear"
        },
        session_id: %{
          type: "string",
          description: "The session ID to use for memory operations"
        },
        data: %{
          type: "any",
          description: "For save: the data to store; For search: the query term; Not used for get/clear"
        }
      }
    }
  end
  
  @impl Adk.Tool
  def execute(%{"action" => "save", "session_id" => session_id, "data" => data}) do
    case Adk.Memory.add_session(:in_memory, session_id, data) do
      :ok -> {:ok, "Data saved to memory for session #{session_id}"}
      {:error, reason} -> {:error, "Failed to save to memory: #{inspect(reason)}"}
    end
  end
  
  def execute(%{"action" => "search", "session_id" => session_id, "data" => query}) do
    case Adk.Memory.search(:in_memory, session_id, query) do
      {:ok, results} -> 
        formatted_results = format_results(results)
        {:ok, "Found #{length(results)} results for session #{session_id}:\n#{formatted_results}"}
      {:error, reason} -> 
        {:error, "Memory search failed: #{inspect(reason)}"}
    end
  end
  
  def execute(%{"action" => "get", "session_id" => session_id}) do
    case Adk.Memory.get_sessions(:in_memory, session_id) do
      {:ok, sessions} -> 
        formatted_sessions = format_results(sessions)
        {:ok, "Retrieved #{length(sessions)} memory entries for session #{session_id}:\n#{formatted_sessions}"}
      {:error, reason} -> 
        {:error, "Failed to retrieve memories: #{inspect(reason)}"}
    end
  end
  
  def execute(%{"action" => "clear", "session_id" => session_id}) do
    case Adk.Memory.clear_sessions(:in_memory, session_id) do
      :ok -> {:ok, "Memory cleared for session #{session_id}"}
      {:error, reason} -> {:error, "Failed to clear memory: #{inspect(reason)}"}
    end
  end
  
  def execute(params) do
    {:error, "Invalid parameters: #{inspect(params)}. Expected action, session_id, and possibly data."}
  end
  
  # Private helper functions
  
  defp format_results(results) do
    results
    |> Enum.with_index(1)
    |> Enum.map(fn {result, index} ->
      "#{index}. #{format_result(result)}"
    end)
    |> Enum.join("\n")
  end
  
  defp format_result(result) when is_binary(result) do
    result
  end
  
  defp format_result(result) when is_map(result) do
    result
    |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
    |> Enum.join(", ")
  end
  
  defp format_result(result) do
    inspect(result)
  end
end