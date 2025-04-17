defmodule Adk.Tools.MemoryTool do
  @moduledoc """
  Implements a memory tool for agent workflows, bridging agent steps to memory operations.

  This tool allows agents to store, retrieve, and search information in the configured memory service. Implements the `Adk.Tool` behaviour.

  Extension points:
  - Add new memory actions by extending the `execute/2` callback.
  - See https://google.github.io/adk-docs/Tools for design rationale.
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
          description:
            "The action to perform: save_state, get_state, add_message, get_history, search_history, clear"
        },
        session_id: %{
          type: "string",
          description: "The session ID to use for memory operations"
        },
        key: %{
          type: "string",
          description: "For save_state/get_state: the key to store/retrieve data under"
        },
        data: %{
          type: "any",
          description:
            "For save_state: the value to store; For add_message: the message map; For search_history: the query term"
        }
      }
    }
  end

  @impl Adk.Tool
  # Save key-value data to the state map
  def execute(
        %{
          "action" => "save_state",
          "session_id" => session_id,
          "key" => key,
          "data" => data
        },
        _context
      ) do
    case Adk.Memory.update_state(:in_memory, session_id, String.to_atom(key), data) do
      :ok -> {:ok, "State saved for key '#{key}' in session #{session_id}"}
      # Use simplified error tuple
      {:error, reason} -> {:error, {:save_state_failed, reason}}
    end
  end

  # Get a specific value from the state map
  def execute(%{"action" => "get_state", "session_id" => session_id, "key" => key}, _context) do
    case Adk.Memory.get_state(:in_memory, session_id, String.to_atom(key)) do
      {:ok, value} -> {:ok, "Retrieved state for key '#{key}':\n#{format_result(value)}"}
      {:error, reason} -> {:error, {:get_state_failed, reason}}
    end
  end

  # Add a message (event) to the history list
  # Assumes 'data' contains the options for Adk.Event.new/1 (e.g., %{author: :user, content: "..."})
  def execute(
        %{"action" => "add_message", "session_id" => session_id, "data" => event_opts},
        _context
      )
      when is_map(event_opts) do
    # Ensure author is present, convert keys to atoms if needed
    processed_opts =
      event_opts
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Enum.into(%{})

    if Map.has_key?(processed_opts, :author) do
      case Adk.Memory.add_message(:in_memory, session_id, processed_opts) do
        :ok -> {:ok, "Message event added to history for session #{session_id}"}
        {:error, reason} -> {:error, {:add_message_failed, reason}}
      end
    else
      {:error,
       {:invalid_params, "Missing required 'author' field in 'data' for add_message action."}}
    end
  end

  # Get the full event history list
  def execute(%{"action" => "get_history", "session_id" => session_id}, _context) do
    case Adk.Memory.get_history(:in_memory, session_id) do
      {:ok, history} ->
        # History is now a list of Adk.Event structs
        formatted_history = format_results(history)

        {:ok,
         "Retrieved #{length(history)} history events for session #{session_id}:\n#{formatted_history}"}

      {:error, reason} ->
        {:error, {:get_history_failed, reason}}
    end
  end

  # Search within the event history
  def execute(
        %{"action" => "search_history", "session_id" => session_id, "data" => query},
        _context
      ) do
    case Adk.Memory.search(:in_memory, session_id, query) do
      {:ok, results} ->
        # Results are Adk.Event structs
        formatted_results = format_results(results)

        {:ok,
         "Found #{length(results)} history results for session #{session_id}:\n#{formatted_results}"}

      {:error, reason} ->
        {:error, {:search_history_failed, reason}}
    end
  end

  def execute(%{"action" => "clear", "session_id" => session_id}, _context) do
    case Adk.Memory.clear_sessions(:in_memory, session_id) do
      :ok -> {:ok, "Memory cleared for session #{session_id}"}
      {:error, reason} -> {:error, {:clear_sessions_failed, reason}}
    end
  end

  # Catch-all for invalid parameters or actions
  def execute(params, _context) do
    {:error,
     {:invalid_params,
      "Invalid parameters or action: #{inspect(params)}. Expected action, session_id, and possibly key/data."}}
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

  defp format_result(%Adk.Event{} = event) do
    # Custom formatting for Event structs
    """
    Event ID: #{event.id}
      Timestamp: #{event.timestamp}
      Author: #{event.author}
      Session: #{event.session_id}
      Invocation: #{event.invocation_id || "N/A"}
      Content: #{inspect(event.content)}
      Tool Calls: #{inspect(event.tool_calls)}
      Tool Results: #{inspect(event.tool_results)}
    """
  end

  defp format_result(result) when is_map(result) do
    # Nicer formatting for other maps
    result
    |> Enum.map_join("\n  ", fn {key, value} -> "- #{key}: #{inspect(value)}" end)
  end

  defp format_result(result) do
    inspect(result)
  end
end
