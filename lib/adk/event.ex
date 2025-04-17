defmodule Adk.Event do
  @moduledoc """
  Represents a single event or interaction within an Adk session.

  This struct aligns conceptually with event models used in similar frameworks,
  capturing details about who initiated the event, its content, and any
  associated tool interactions.
  """

  @typedoc """
  The type representing an Adk event.

  Fields:
  * `:id` - A unique identifier for the event (typically a UUID).
  * `:type` - The type of the event (e.g., "user_message", "model_response").
  * `:payload` - The primary content of the event (e.g., user message, model response text). Can be a string or structured map.
  * `:timestamp` - The time the event occurred.
  * `:session_id` - The identifier of the session this event belongs to.
  * `:invocation_id` - An identifier linking events within a single top-level `Adk.run` invocation.
  * `:author` - Who generated the event (`:user`, `:model`, `:tool`, `:agent`, or a custom atom).
  * `:content` - The primary content of the event (e.g., user message, model response text). Can be a string or structured map.
  * `:tool_calls` - A list of tool calls requested by the model in this event. Each item is a map describing the call.
  * `:tool_results` - A list of results from tool executions corresponding to tool calls. Each item is a map containing the result.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t() | atom() | nil,
          payload: map() | String.t() | nil,
          timestamp: NaiveDateTime.t(),
          session_id: String.t() | nil,
          invocation_id: String.t() | nil,
          author: :user | :model | :tool | :agent | atom() | nil,
          content: map() | String.t() | nil,
          tool_calls: list(map()) | nil,
          tool_results: list(map()) | nil
        }

  @derive {JSON.Encoder, except: []}
  defstruct [
    :id,
    :type,
    :payload,
    :timestamp,
    :session_id,
    :invocation_id,
    :author,
    :content,
    :tool_calls,
    :tool_results
  ]

  @doc """
  Creates a new Event struct with defaults.

  Generates a UUID for `:id` and sets the current UTC time for `:timestamp`.
  Requires `:session_id` and `:author` keys in the input map or keyword list. Other fields default to `nil`.
  """
  def new(opts) when is_list(opts) do
    new(Enum.into(opts, %{}))
  end

  def new(opts) when is_map(opts) do
    struct!(__MODULE__,
      id: Map.get_lazy(opts, :id, fn -> random_id() end),
      type: Map.get(opts, :type),
      payload: Map.get(opts, :payload),
      timestamp:
        Map.get_lazy(opts, :timestamp, fn ->
          NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:microsecond)
        end),
      session_id: Map.get(opts, :session_id),
      invocation_id: Map.get(opts, :invocation_id),
      author: Map.get(opts, :author),
      content: Map.get(opts, :content),
      tool_calls: Map.get(opts, :tool_calls),
      tool_results: Map.get(opts, :tool_results)
    )
  end

  defp random_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  @doc """
  Serializes the event struct to a JSON string.
  Returns {:ok, json} or {:error, reason}.
  """
  def to_json(event) do
    try do
      {:ok, JSON.encode!(event)}
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Deserializes a JSON string into a map or event struct.
  Returns {:ok, map} or {:error, reason}.
  """
  def from_json(json) do
    case JSON.decode(json) do
      {:ok, map} ->
        struct_keys = Map.keys(__MODULE__.__struct__())

        atomized =
          for {k, v} <- map, into: %{} do
            key =
              if is_binary(k) and String.to_atom(k) in struct_keys do
                String.to_atom(k)
              else
                k
              end

            value =
              case key do
                :author when is_binary(v) ->
                  case v do
                    "user" -> :user
                    "model" -> :model
                    "tool" -> :tool
                    "agent" -> :agent
                    _ -> v
                  end

                _ ->
                  v
              end

            {key, value}
          end

        {:ok, struct(__MODULE__, atomized)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
