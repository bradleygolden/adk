defmodule Adk.Agent.Llm.PromptBuilder.Langchain do
  @moduledoc """
  Prompt builder for the Langchain integration.
  Handles both direct format for LLM agent and compatibility with existing code.
  """

  @behaviour Adk.Agent.Llm.PromptBuilder

  @impl true
  def build_messages(state) do
    cond do
      is_map(state) && Map.has_key?(state, :config) && is_map(state.config) ->
        build_from_llm_state(state)

      is_map(state) && Map.has_key?(state, :history) && Map.has_key?(state, :input) ->
        build_from_context(state)

      true ->
        {:error, {:invalid_state_format, state}}
    end
  end

  # For testing purposes only - allows direct access to build_from_context in test env
  if Mix.env() == :test do
    @doc false
    def test_build_from_context(state) do
      build_from_context(state)
    end
  end

  defp build_from_context(%{config: config, history: history, input: input}) do
    messages = []
    system_prompt = config.system_prompt

    enhanced_system_prompt =
      if Map.get(config, :output_schema) do
        Adk.PromptTemplate.with_json_output(system_prompt, config.output_schema)
      else
        system_prompt
      end

    messages =
      if enhanced_system_prompt do
        [%{role: "system", content: enhanced_system_prompt} | messages]
      else
        messages
      end

    messages =
      if history && length(history) > 0 do
        messages ++ history
      else
        messages
      end

    messages =
      if input do
        messages ++ [%{role: "user", content: input}]
      else
        messages
      end

    {:ok, messages}
  end

  defp build_from_llm_state(state) do
    messages = []
    system_prompt = state.config.system_prompt

    enhanced_system_prompt =
      if Map.get(state.config, :output_schema) do
        Adk.PromptTemplate.with_json_output(system_prompt, state.config.output_schema)
      else
        system_prompt
      end

    messages =
      if enhanced_system_prompt do
        [%{role: "system", content: enhanced_system_prompt} | messages]
      else
        messages
      end

    messages =
      if Map.get(state, :conversation_history) && length(state.conversation_history) > 0 do
        Enum.reduce(state.conversation_history, messages, fn message, acc ->
          [message | acc]
        end)
      else
        messages
      end

    {:ok, Enum.reverse(messages)}
  end
end
