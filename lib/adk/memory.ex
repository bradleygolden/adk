defmodule Adk.Memory do
  @moduledoc """
  Behaviour and utilities for implementing memory services in the Adk framework.

  ## Configuration

      config :adk, :memory_backend, Adk.Memory.InMemory

  By default, the in-memory backend is used. You can override this in your config.

  ## Usage

  You can call memory functions with or without specifying the backend. If omitted, the configured backend is used:

      Adk.Memory.add_session("session_id", %{foo: :bar})
      Adk.Memory.add_session(MyCustomBackend, "session_id", %{foo: :bar})
  """

  @doc """
  Add a session to memory.

  ## Parameters
    * `session_id` - A unique identifier for the session
    * `data` - The data to store for the session
  """
  @callback add_session(session_id :: String.t(), data :: any()) ::
              :ok | {:error, {:session_add_failed, reason :: term()}}

  @doc """
  Add an event to the history for a given session.

  This function constructs an `Adk.Event` using the provided options
  and adds it to the session's history.

  ## Parameters
    * `session_id` - A unique identifier for the session.
    * `opts` - Keyword list or map containing data for the `Adk.Event`.
      Must include `:author`. Other keys like `:content`, `:tool_calls`,
      `:tool_results`, `:invocation_id` are optional. See `Adk.Event.new/1`.
  """
  @callback add_message(session_id :: String.t(), opts :: keyword() | map()) ::
              :ok
              | {:error, {:message_add_failed, reason :: term()}}
  # Session might be implicitly created by add_message
  # | {:error, {:session_not_found, session_id :: String.t()}}

  @doc """
  Get the full event history for a given session.

  ## Parameters
    * `session_id` - The session ID to get history for.
  """
  @callback get_history(session_id :: String.t()) ::
              {:ok, list(Adk.Event.t())}
              | {:error, {:history_fetch_failed, reason :: term()}}
              | {:error, {:session_not_found, session_id :: String.t()}}

  @doc """
  Update a specific key-value pair in the state map for a given session.

  ## Parameters
    * `session_id` - The session ID to update state for
    * `key` - The key (atom or string) to update in the state map
    * `value` - The new value for the key
  """
  @callback update_state(session_id :: String.t(), key :: atom() | String.t(), value :: any()) ::
              :ok
              | {:error, {:state_update_failed, reason :: term()}}
              | {:error, {:session_not_found, session_id :: String.t()}}

  @doc """
  Get the value of a specific key from the state map for a given session.

  ## Parameters
    * `session_id` - The session ID to get state from
    * `key` - The key (atom or string) to retrieve from the state map
  """
  @callback get_state(session_id :: String.t(), key :: atom() | String.t()) ::
              {:ok, any()}
              | {:error, {:state_fetch_failed, reason :: term()}}
              | {:error, {:key_not_found, key :: atom() | String.t()}}
              | {:error, {:session_not_found, session_id :: String.t()}}

  @doc """
  Get the entire state map for a given session.

  ## Parameters
    * `session_id` - The session ID to get the full state for
  """
  @callback get_full_state(session_id :: String.t()) ::
              {:ok, map()}
              | {:error, {:state_fetch_failed, reason :: term()}}
              | {:error, {:session_not_found, session_id :: String.t()}}

  @doc """
  Search memory for sessions matching the query.

  ## Parameters
    * `session_id` - The session ID to search in (if applicable)
    * `query` - The search query (can be string or structured data)
  """
  # Session ID might not be relevant for all search types
  @callback search(session_id :: String.t(), query :: any()) ::
              {:ok, [any()]} | {:error, {:search_failed, reason :: term()}}

  @doc """
  Get all sessions for the given ID.

  ## Parameters
    * `session_id` - The session ID to get data for
  """
  @callback get_sessions(session_id :: String.t()) ::
              {:ok, [any()]}
              | {:error, {:session_fetch_failed, reason :: term()}}
              | {:error, {:session_not_found, session_id :: String.t()}}

  @doc """
  Clear all sessions for the given ID.

  ## Parameters
    * `session_id` - The session ID to clear data for
  """
  # May succeed even if session doesn't exist
  @callback clear_sessions(session_id :: String.t()) ::
              :ok | {:error, {:session_clear_failed, reason :: term()}}

  # --- Public API with default backend resolution ---

  def add_session(session_id, data), do: add_session(resolve_backend(), session_id, data)

  def add_session(service, session_id, data),
    do: get_service_module(service).add_session(session_id, data)

  def add_message(session_id, opts), do: add_message(resolve_backend(), session_id, opts)

  def add_message(service, session_id, opts),
    do: get_service_module(service).add_message(session_id, opts)

  def get_history(session_id), do: get_history(resolve_backend(), session_id)
  def get_history(service, session_id), do: get_service_module(service).get_history(session_id)

  def update_state(session_id, key, value),
    do: update_state(resolve_backend(), session_id, key, value)

  def update_state(service, session_id, key, value),
    do: get_service_module(service).update_state(session_id, key, value)

  def get_state(session_id, key), do: get_state(resolve_backend(), session_id, key)

  def get_state(service, session_id, key),
    do: get_service_module(service).get_state(session_id, key)

  def get_full_state(session_id), do: get_full_state(resolve_backend(), session_id)

  def get_full_state(service, session_id),
    do: get_service_module(service).get_full_state(session_id)

  def search(session_id, query), do: search(resolve_backend(), session_id, query)

  def search(service, session_id, query),
    do: get_service_module(service).search(session_id, query)

  def get_sessions(session_id), do: get_sessions(resolve_backend(), session_id)
  def get_sessions(service, session_id), do: get_service_module(service).get_sessions(session_id)

  def clear_sessions(session_id), do: clear_sessions(resolve_backend(), session_id)

  def clear_sessions(service, session_id),
    do: get_service_module(service).clear_sessions(session_id)

  # --- Backend resolution helpers ---

  defp resolve_backend do
    Application.get_env(:adk, :memory_backend, :in_memory)
  end

  @doc false
  def get_service_module(service) when is_atom(service) do
    cond do
      service == :in_memory ->
        Adk.Memory.InMemory

      function_exported?(service, :add_session, 2) ->
        service

      true ->
        {:error, {:unknown_memory_service, service}}
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
      def add_session(_session_id, _data), do: {:error, {:not_implemented, :add_session}}

      @impl Adk.Memory
      def add_message(_session_id, _opts),
        do: {:error, {:not_implemented, :add_message}}

      @impl Adk.Memory
      def get_history(_session_id),
        do: {:error, {:not_implemented, :get_history}}

      @impl Adk.Memory
      def update_state(_session_id, _key, _value), do: {:error, {:not_implemented, :update_state}}

      @impl Adk.Memory
      def get_state(_session_id, _key), do: {:error, {:not_implemented, :get_state}}

      @impl Adk.Memory
      def get_full_state(_session_id), do: {:error, {:not_implemented, :get_full_state}}

      @impl Adk.Memory
      def search(_session_id, _query), do: {:error, {:not_implemented, :search}}

      @impl Adk.Memory
      def get_sessions(_session_id), do: {:error, {:not_implemented, :get_sessions}}

      @impl Adk.Memory
      def clear_sessions(_session_id), do: {:error, {:not_implemented, :clear_sessions}}

      # Allow overriding default implementations
      defoverridable add_session: 2,
                     # Arity remains 2 (session_id, opts)
                     add_message: 2,
                     get_history: 1,
                     update_state: 3,
                     get_state: 2,
                     get_full_state: 1,
                     search: 2,
                     get_sessions: 1,
                     clear_sessions: 1
    end
  end
end
