defmodule Adk.Memory.InMemory do
  @moduledoc """
  Reference in-memory implementation of the Adk.Memory service.

  Stores session data in an ETS table. Suitable for development and testing, but not for production use as data will be lost on restart.

  Extension points:
  - Add property tests (e.g., with StreamData) to ensure correctness under concurrency.
  - See https://google.github.io/adk-docs/Memory for design rationale.
  """
  use Adk.Memory

  alias Adk.Event

  @table :adk_memory_sessions

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(_opts \\ []) do
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])
    end

    {:ok, self()}
  end

  defp get_or_init_session_data(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, session_data}] -> session_data
      [] -> %{history: [], state: %{}}
    end
  end

  @impl Adk.Memory
  def add_session(session_id, data) do
    update_state(session_id, :initial_data, data)
  end

  @impl Adk.Memory
  def add_message(session_id, opts) when is_list(opts) or is_map(opts) do
    event_opts_map =
      case opts do
        kw when is_list(kw) -> Enum.into(kw, %{})
        map when is_map(map) -> map
      end
      |> Map.put_new(:session_id, session_id)

    if Map.has_key?(event_opts_map, :author) do
      session_data = get_or_init_session_data(session_id)
      event = Event.new(event_opts_map)
      updated_history = [event | session_data.history]
      updated_session_data = %{session_data | history: updated_history}
      :ets.insert(@table, {session_id, updated_session_data})
      :ok
    else
      {:error, {:message_add_failed, "Missing required :author field in opts for Adk.Event"}}
    end
  end

  @impl Adk.Memory
  def get_history(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, session_data}] ->
        {:ok, Enum.reverse(session_data.history)}

      [] ->
        {:error, {:session_not_found, session_id}}
    end
  end

  @impl Adk.Memory
  def update_state(session_id, key, value) do
    session_data = get_or_init_session_data(session_id)
    updated_state_map = Map.put(session_data.state, key, value)
    updated_session_data = %{session_data | state: updated_state_map}
    :ets.insert(@table, {session_id, updated_session_data})
    :ok
  end

  @impl Adk.Memory
  def get_state(session_id, key) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, session_data}] ->
        case Map.fetch(session_data.state, key) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, {:key_not_found, key}}
        end

      [] ->
        {:error, {:session_not_found, session_id}}
    end
  end

  @impl Adk.Memory
  def get_full_state(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, session_data}] -> {:ok, session_data.state}
      [] -> {:error, {:session_not_found, session_id}}
    end
  end

  @impl Adk.Memory
  def search(session_id, query) do
    history =
      case :ets.lookup(@table, session_id) do
        [{^session_id, session_data}] -> session_data.history
        [] -> []
      end

    results =
      Enum.filter(history, fn event ->
        content = Map.get(event, :content)

        cond do
          is_binary(query) and is_binary(content) -> String.contains?(content, query)
          is_struct(query, Regex) and is_binary(content) -> Regex.match?(query, content)
          true -> false
        end
      end)

    {:ok, Enum.reverse(results)}
  end

  @impl Adk.Memory
  def get_sessions(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, session_data}] -> {:ok, session_data}
      [] -> {:error, {:session_not_found, session_id}}
    end
  end

  @impl Adk.Memory
  def clear_sessions(session_id) do
    :ets.delete(@table, session_id)
    :ok
  end

  def clear_all_sessions do
    :ets.delete_all_objects(@table)
    :ok
  end
end
