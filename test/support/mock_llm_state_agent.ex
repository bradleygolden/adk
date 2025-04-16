defmodule Adk.Test.MockLLMStateAgent do
  @moduledoc """
  An Agent to hold the expected response for the MockLLMProvider across processes.
  """
  use Agent

  @doc """
  Starts the agent.
  """
  def start_link(_opts) do
    # Start the agent and link it to the current process supervisor (usually the test process)
    # Name it so it can be accessed globally by name.
    Agent.start_link(fn -> nil end, name: __MODULE__)
  end

  @doc """
  Sets the expected response content.
  """
  def set_response(response) when is_binary(response) do
    Agent.update(__MODULE__, fn _state -> response end)
  end

  @doc """
  Gets the currently set expected response content. Returns nil if not set.
  """
  def get_response() do
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Clears the expected response content (sets it back to nil).
  """
  def clear_response() do
    Agent.update(__MODULE__, fn _state -> nil end)
  end
end
