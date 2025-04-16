defmodule Adk.Agents.Llm.LangchainPromptBuilder do
  @moduledoc """
  Prompt builder for the Langchain Agent.
  Adapts the state structure for prompt message generation.
  """

  @behaviour Adk.Agents.Llm.PromptBuilderBehaviour

  # Alias the correct State module
  alias Adk.Agents.Langchain.State

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
    # Assuming history is already in the correct format [%{role: "...", content: "..."}, ...]
    messages =
      Enum.reduce(state.conversation_history, messages, fn message, acc ->
        [message | acc]
      end)

    # Reverse to maintain chronological order
    {:ok, Enum.reverse(messages)}
  end
end
