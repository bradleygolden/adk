defmodule Adk.A2A do
  @moduledoc """
  Agent-to-Agent (A2A) protocol for communication between agents.

  This module provides utilities for agents to communicate with each other,
  either within the same Elixir process or across different systems via HTTP.
  """

  @doc """
  Call another agent by reference (pid or name).

  ## Parameters
    * `agent` - The agent to call (pid or name)
    * `input` - The input to provide to the agent
    * `metadata` - Optional metadata about the call

  ## Examples
      iex> Adk.A2A.call_local(travel_agent, "Plan a trip to Paris")
      {:ok, %{output: "Here's a travel plan for Paris..."}}
  """
  def call_local(agent, input, metadata \\ %{}) do
    # For local calls, simply use the existing run function
    Adk.run(agent, input)
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
    # In a real implementation, you would use a library like HTTPoison

    # Mock response for demonstration purposes
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
    # In a real implementation, this would register a route in a web framework
    # like Phoenix or Plug to expose the agent at the given path
    # For now, we'll just return :ok for demonstration
    :ok
  end

  # Private helper functions

  defp add_metadata({:ok, result}, metadata) when is_map(result) do
    # Add metadata to the result
    {:ok, Map.put(result, :metadata, metadata)}
  end

  defp add_metadata(other_result, _metadata) do
    # For error cases or unexpected formats, just return as is
    other_result
  end
end
