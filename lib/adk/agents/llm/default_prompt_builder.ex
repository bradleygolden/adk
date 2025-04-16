defmodule Adk.Agents.Llm.DefaultPromptBuilder do
  @moduledoc """
  Default implementation of the PromptBuilderBehaviour.
  Builds prompt messages for LLM agents using a standard format.
  """

  @behaviour Adk.Agents.Llm.PromptBuilderBehaviour

  alias Adk.Agents.LLM.State

  @impl true
  def build_messages(%State{} = state) do
    messages = []

    # Add system prompt if present
    messages =
      if state.config.system_prompt do
        [%{role: "system", content: state.config.system_prompt} | messages]
      else
        messages
      end

    # Add conversation history
    messages =
      Enum.reduce(state.conversation_history, messages, fn message, acc ->
        [message | acc]
      end)

    # Reverse to maintain chronological order
    {:ok, Enum.reverse(messages)}
  end
end
