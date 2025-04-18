defmodule Adk.Agent.Llm.PromptBuilder do
  @moduledoc """
  Defines the behaviour for modules that build prompt messages for LLM agents.

  Implementations can customize how system prompts, tool descriptions, schema instructions,
  and conversation history are formatted for specific LLM providers or agent needs.
  """

  alias Adk.Agent.LLM.State

  @doc """
  Builds the final list of messages to be sent to the LLM.

  Receives the full agent state, allowing access to configuration (like tools,
  schemas, provider-specific options) and conversation history.

  Returns a list of maps, where each map represents a message with at least
  `:role` and `:content` keys, compatible with the target LLM provider's API.
  """
  @callback build_messages(state :: State.t()) :: {:ok, list(map())} | {:error, term()}
end
