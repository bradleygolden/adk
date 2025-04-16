defmodule Adk.Event do
  @moduledoc """
  Represents a single event or interaction within an ADK session.

  This struct aligns conceptually with event models used in similar frameworks,
  capturing details about who initiated the event, its content, and any
  associated tool interactions.
  """

  @typedoc """
  The type representing an ADK event.

  Fields:
  * `:id` - A unique identifier for the event (typically a UUID).
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
          timestamp: NaiveDateTime.t(),
          session_id: String.t(),
          invocation_id: String.t() | nil,
          author: :user | :model | :tool | :agent | atom(),
          content: map() | String.t() | nil,
          tool_calls: list(map()) | nil,
          tool_results: list(map()) | nil
        }

  defstruct [
    :id,
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
  @spec new(map() | keyword()) :: t()
  def new(opts) when is_list(opts) do
    # Allow keyword list for convenience, convert to map
    new(Enum.into(opts, %{}))
  end

  def new(opts) when is_map(opts) do
    session_id = Map.fetch!(opts, :session_id)
    author = Map.fetch!(opts, :author)

    struct!(__MODULE__,
      id: UUID.uuid4(),
      timestamp: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:microsecond),
      session_id: session_id,
      author: author,
      invocation_id: Map.get(opts, :invocation_id),
      content: Map.get(opts, :content),
      tool_calls: Map.get(opts, :tool_calls),
      tool_results: Map.get(opts, :tool_results)
    )
  end
end
