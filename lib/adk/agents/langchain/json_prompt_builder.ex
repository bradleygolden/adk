defmodule Adk.Agents.Langchain.JsonPromptBuilder do
  @moduledoc """
  A prompt builder that automatically adds JSON output requirements to system prompts.

  This builder enhances system prompts with explicit instructions for LLMs to format
  their responses as JSON objects that match the expected output schema.
  """

  alias Adk.Agents.Langchain.State
  alias Adk.PromptTemplate

  @doc """
  Builds the messages to be sent to the LLM, with JSON formatting instructions.

  This function enhances the system prompt with instructions to format output as JSON
  according to the provided output schema.

  ## Parameters
    * `state` - The agent state containing configuration and history

  ## Returns
    * `{:ok, messages}` - List of formatted message maps ready for the LLM
    * `{:error, reason}` - Error with reason if building messages fails
  """
  def build_messages(%State{} = state) do
    # Get the system prompt from the config
    system_prompt = state.config.system_prompt

    # If there's an output schema, enhance the system prompt with JSON formatting instructions
    enhanced_system_prompt =
      if state.config.output_schema do
        PromptTemplate.with_json_output(system_prompt, state.config.output_schema)
      else
        system_prompt
      end

    # Create the messages array with the enhanced system prompt
    messages = [
      %{
        role: "system",
        content: enhanced_system_prompt
      }
    ]

    # Add conversation history messages
    messages =
      messages ++
        Enum.map(state.conversation_history, fn %{role: role, content: content} ->
          %{role: role, content: content}
        end)

    {:ok, messages}
  end
end
