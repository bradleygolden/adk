defmodule Adk.Memory.InMemory do
  @moduledoc """
  A simple in-memory implementation of the Memory service.

  This module stores session data in an Agent process, making it suitable for
  development and testing, but not for production use as data will be lost when
  the application restarts.
  """
  use Adk.Memory
  use Agent

  alias Adk.Event

  def start_link(_opts \\ []) do
    # Initialize state as a map where keys are session_ids
    # and values are maps containing :history and :state
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  # --- Internal Helper ---
  defp get_or_init_session_data(state, session_id) do
    Map.get(state, session_id, %{history: [], state: %{}})
  end

  # --- Adk.Memory Callbacks ---

  @impl Adk.Memory
  def add_session(session_id, data) do
    # Note: This function might be less useful now.
    # It currently adds arbitrary data to the 'state' map under a generic key.
    # Consider deprecating or refining its purpose.
    update_state(session_id, :initial_data, data)
  end

  @impl Adk.Memory
  def add_message(session_id, opts) when is_list(opts) or is_map(opts) do
    # Normalize opts to a map and ensure session_id is present
    event_opts_map =
      case opts do
        kw when is_list(kw) -> Enum.into(kw, %{})
        map when is_map(map) -> map
      end
      # Ensure session_id is there
      |> Map.put_new(:session_id, session_id)

    # Validate required fields for Event.new (author)
    if Map.has_key?(event_opts_map, :author) do
      Agent.update(__MODULE__, fn state ->
        session_data = get_or_init_session_data(state, session_id)
        # Event.new now accepts a map
        event = Event.new(event_opts_map)

        # Prepend event to keep chronological order (newest first) easily accessible
        updated_history = [event | session_data.history]
        updated_session_data = %{session_data | history: updated_history}
        Map.put(state, session_id, updated_session_data)
      end)

      :ok
    else
      {:error, {:message_add_failed, "Missing required :author field in opts for Adk.Event"}}
    end
  end

  @impl Adk.Memory
  def get_history(session_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state, session_id) do
        nil ->
          # Session doesn't exist
          {:error, {:session_not_found, session_id}}

        session_data ->
          # Session exists, return reversed history
          {:ok, Enum.reverse(session_data.history)}
      end
    end)
  end

  @impl Adk.Memory
  def update_state(session_id, key, value) do
    Agent.update(__MODULE__, fn state ->
      session_data = get_or_init_session_data(state, session_id)
      updated_state_map = Map.put(session_data.state, key, value)
      updated_session_data = %{session_data | state: updated_state_map}
      Map.put(state, session_id, updated_session_data)
    end)

    :ok
  end

  @impl Adk.Memory
  def get_state(session_id, key) do
    Agent.get(__MODULE__, fn state ->
      # Check if session exists first
      session_data = Map.get(state, session_id)

      if session_data do
        case Map.fetch(session_data.state, key) do
          {:ok, value} -> {:ok, value}
          # Key doesn't exist in state map
          :error -> {:error, {:key_not_found, key}}
        end
      else
        # Session itself doesn't exist (though get_or_init_session_data usually prevents this path in updates)
        {:error, {:session_not_found, session_id}}
      end
    end)
  end

  @impl Adk.Memory
  def get_full_state(session_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state, session_id) do
        nil -> {:error, {:session_not_found, session_id}}
        session_data -> {:ok, session_data.state}
      end
    end)
  end

  @impl Adk.Memory
  def search(session_id, query) do
    # Simple search implementation: searches event content in history
    history =
      Agent.get(__MODULE__, fn state ->
        get_or_init_session_data(state, session_id).history
      end)

    results =
      Enum.filter(history, fn event ->
        # Handle events without :content or with non-binary content
        # Event struct access
        content = Map.get(event, :content)

        cond do
          is_binary(query) and is_binary(content) ->
            String.contains?(content, query)

          is_struct(query, Regex) and is_binary(content) ->
            Regex.match?(query, content)

          # Add more sophisticated search logic if needed (e.g., map search on content)
          true ->
            false
        end
      end)

    # Return matching events in chronological order
    {:ok, Enum.reverse(results)}
  end

  @impl Adk.Memory
  def get_sessions(session_id) do
    # Returns the full session data map (history + state) or an error if not found.
    Agent.get(__MODULE__, fn state ->
      case Map.get(state, session_id) do
        nil -> {:error, {:session_not_found, session_id}}
        # Return the whole map {:history, :state}
        session_data -> {:ok, session_data}
      end
    end)
  end

  @impl Adk.Memory
  def clear_sessions(session_id) do
    Agent.update(__MODULE__, &Map.delete(&1, session_id))
    :ok
  end

  # Note: The previous private search helpers (map_contains_query?, etc.)
  # are removed as the basic search now focuses on message content.
  # They could be reintroduced if more complex state searching is required.
end
