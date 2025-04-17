defmodule Adk.Agents.Langchain.JsonPromptBuilderTest do
  use ExUnit.Case

  alias Adk.Agents.Langchain.{JsonPromptBuilder, State, Config}
  alias Adk.Test.Schemas.OutputSchema

  describe "build_messages/1" do
    test "builds messages without output schema" do
      config = %Config{
        name: "test_agent",
        llm_options: %{provider: :openai, api_key: "test", model: "gpt-3.5"},
        system_prompt: "You are a test assistant."
      }

      state = %State{
        session_id: "test_session",
        config: config,
        conversation_history: [
          %{role: "user", content: "Hello"},
          %{role: "assistant", content: "Hi there!"}
        ]
      }

      {:ok, messages} = JsonPromptBuilder.build_messages(state)
      assert length(messages) == 3
      [system_message | conversation] = messages
      assert system_message.role == "system"
      assert system_message.content == "You are a test assistant."
      assert Enum.map(conversation, & &1.role) == ["user", "assistant"]
    end

    test "adds JSON instructions when output schema is present" do
      config = %Config{
        name: "test_agent",
        llm_options: %{provider: :openai, api_key: "test", model: "gpt-3.5"},
        system_prompt: "You are a test assistant.",
        output_schema: OutputSchema
      }

      state = %State{
        session_id: "test_session",
        config: config,
        conversation_history: [
          %{role: "user", content: "Hello"}
        ]
      }

      {:ok, messages} = JsonPromptBuilder.build_messages(state)
      assert length(messages) == 2
      [system_message, user_message] = messages
      assert system_message.role == "system"
      assert String.contains?(system_message.content, "RESPONSE FORMAT")

      assert String.contains?(
               system_message.content,
               "You MUST format your response as a valid JSON"
             )

      assert String.contains?(system_message.content, "Required fields: answer, confidence")
      assert user_message.role == "user"
      assert user_message.content == "Hello"
    end

    test "handles empty conversation history" do
      config = %Config{
        name: "test_agent",
        llm_options: %{provider: :openai, api_key: "test", model: "gpt-3.5"},
        system_prompt: "You are a test assistant."
      }

      state = %State{
        session_id: "test_session",
        config: config,
        conversation_history: []
      }

      {:ok, messages} = JsonPromptBuilder.build_messages(state)
      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "You are a test assistant."
    end
  end
end
