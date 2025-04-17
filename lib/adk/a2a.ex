defmodule Adk.A2A do
  @moduledoc """
  Agent-to-Agent (A2A) protocol for communication between agents.

  This module provides utilities for agents to communicate with each other,
  either within the same Elixir process or across different systems via HTTP.

  ## Message Envelope Structure

      %{
        id: String.t(),
        type: String.t() | atom(),
        payload: any(),
        sender: any(),
        recipient: any(),
        metadata: map() | nil,
        timestamp: NaiveDateTime.t() | nil
      }

  All agent-to-agent messages should be wrapped in this envelope for consistency and traceability.
  """

  @type envelope :: %{
          id: String.t(),
          type: String.t() | atom(),
          payload: any(),
          sender: any(),
          recipient: any(),
          metadata: map() | nil,
          timestamp: NaiveDateTime.t() | nil
        }

  @callback send_message(recipient :: any(), payload :: any(), opts :: map()) ::
              {:ok, envelope()} | {:error, term()}
  @callback handle_message(envelope(), state :: any()) :: {:ok, any()} | {:error, term()}

  @doc """
  Send a message to another agent, wrapping it in an envelope.
  """
  @spec send_message(any(), any(), map()) :: {:ok, envelope()} | {:error, term()}
  def send_message(recipient, payload, opts \\ %{}) do
    envelope = %{
      id: random_id(),
      type: Map.get(opts, :type, "a2a_message"),
      payload: payload,
      sender: Map.get(opts, :sender, self()),
      recipient: recipient,
      metadata: Map.get(opts, :metadata),
      timestamp: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:microsecond)
    }

    # In a real system, this would route the message to the recipient (local or remote)
    # For now, just return the envelope
    {:ok, envelope}
  end

  @doc """
  Handle an incoming agent-to-agent message envelope.
  """
  @spec handle_message(envelope(), any()) :: {:ok, any()} | {:error, term()}
  def handle_message(%{payload: payload} = _envelope, state) do
    # In a real system, this would dispatch to the appropriate handler based on type, etc.
    {:ok, {payload, state}}
  end

  @doc """
  Call another agent by reference (pid or name).

  ## Parameters
    * `agent` - The agent to call (pid or name)
    * `input` - The input to provide to the agent
    * `metadata` - Optional metadata about the call
    * `runner` - (optional) a function to use instead of Adk.run/2, for testing or customization

  ## Examples
      iex> Adk.A2A.call_local(travel_agent, "Plan a trip to Paris")
      {:ok, %{output: "Here's a travel plan for Paris..."}}
  """
  def call_local(agent, input, metadata \\ %{}, runner \\ &Adk.run/2) do
    runner.(agent, input)
    |> add_metadata(metadata)
  end

  @doc """
  Call a remote agent via HTTP.

  ## Parameters
    * `url` - The URL of the remote agent's /run endpoint
    * `input` - The input to provide to the agent
    * `metadata` - Optional metadata to send with the request
    * `options` - Additional HTTP request options

  ## Examples
      iex> Adk.A2A.call_remote("https://travel-agent.example.com/run", "Plan a trip to Paris")
      {:ok, %{output: "Here's a travel plan for Paris..."}}
  """
  def call_remote(url, _input, metadata \\ %{}, _options \\ []) do
    # This implementation depends on having an HTTP client
    # For simplicity, we'll use a mock implementation
    {:ok, %{output: "Mock response from remote agent at #{url}", metadata: metadata}}
  end

  @doc """
  Register an agent to be available via HTTP.

  ## Parameters
    * `agent` - The agent to register (pid or name)
    * `path` - The path to make the agent available at (defaults to /run)

  ## Examples
      iex> Adk.A2A.register_http(travel_agent, "/agents/travel")
      :ok
  """
  def register_http(_agent, _path \\ "/run") do
    :ok
  end

  # Private helper functions

  defp add_metadata({:ok, result}, metadata) when is_map(result) do
    {:ok, Map.put(result, :metadata, metadata)}
  end

  defp add_metadata(other_result, _metadata) do
    other_result
  end

  defp random_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
