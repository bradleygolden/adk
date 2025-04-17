defmodule Adk.Agents.Langchain.DefaultPromptBuilderTest do
  use ExUnit.Case

  alias Adk.Agents.Langchain.{DefaultPromptBuilder, State, Config}
  alias Adk.Test.Schemas.OutputSchema

  # Sample schema for testing
  # defmodule TestSchema do
  #   @derive Jason.Encoder
  #   @enforce_keys [:response]
  #   defstruct [:response, :details, is_complete: false, items: []]
  # end

  describe "build_messages/1" do
    test "builds basic messages without output schema" do
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

      {:ok, messages} = DefaultPromptBuilder.build_messages(state)

      assert length(messages) == 3
      [system_message | conversation] = messages
      assert system_message.role == "system"
      assert system_message.content == "You are a test assistant."
      assert Enum.map(conversation, & &1.role) == ["user", "assistant"]
      assert Enum.map(conversation, & &1.content) == ["Hello", "Hi there!"]
    end

    test "enhances system prompt with JSON instructions when output schema is present" do
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

      {:ok, messages} = DefaultPromptBuilder.build_messages(state)

      assert length(messages) == 2
      [system_message, user_message] = messages

      # Check that JSON formatting instructions were added
      assert system_message.role == "system"
      assert String.contains?(system_message.content, "RESPONSE FORMAT")

      assert String.contains?(
               system_message.content,
               "You MUST format your response as a valid JSON"
             )

      assert String.contains?(system_message.content, "Required fields: answer, confidence")

      # Check that original prompt is preserved
      assert String.contains?(system_message.content, "You are a test assistant.")

      # Check that conversation history is preserved
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

      {:ok, messages} = DefaultPromptBuilder.build_messages(state)

      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "You are a test assistant."
    end
  end
end
