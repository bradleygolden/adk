defmodule Adk.Agent.Llm.PromptBuilder.Default do
  @moduledoc """
  Default implementation of the PromptBuilder behaviour.
  Builds prompt messages for LLM agents using a standard format.

  Accepts a context map: `%{config: %Adk.Agent.LLM{}, history: list(), input: any()}`
  """

  @behaviour Adk.Agent.Llm.PromptBuilder

  @doc """
  Builds a list of messages suitable for an LLM chat endpoint.

  Includes system prompt (if configured), historical messages, and the current user input.
  """
  def build_messages(%{config: config, history: history, input: input}) do
    system_message =
      if config.system_prompt do
        [%{role: "system", content: config.system_prompt}]
      else
        []
      end

    history_messages = if is_list(history), do: history, else: []
    user_message = %{role: "user", content: to_string(input)}
    messages = system_message ++ history_messages ++ [user_message]
    {:ok, messages}
  end

  def build_messages(invalid_context) do
    {:error, {:invalid_prompt_context, invalid_context}}
  end
end
