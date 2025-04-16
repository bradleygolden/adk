defmodule Adk.Agents.Langchain.DefaultPromptBuilder do
  @moduledoc """
  Default prompt builder implementation for Langchain agents.
  """

  alias Adk.Agents.Langchain.State

  @doc """
  Builds the messages to be sent to the LLM.
  """
  @spec build_messages(State.t()) :: {:ok, list(map())} | {:error, term()}
  def build_messages(%State{} = state) do
    messages = [
      %{
        role: "system",
        content: state.config.system_prompt
      }
    ]

    # Add conversation history
    messages =
      messages ++
        Enum.map(state.conversation_history, fn %{role: role, content: content} ->
          %{role: role, content: content}
        end)

    {:ok, messages}
  end
end
