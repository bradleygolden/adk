defmodule Adk.Agents.Llm.LangchainPromptBuilderTest do
  use ExUnit.Case

  alias Adk.Agents.Llm.LangchainPromptBuilder
  alias Adk.Agents.Langchain.{State, Config}

  @default_name "test_agent"
  @default_llm_options %{provider: :openai, model: "gpt-3.5-turbo", api_key: "dummy"}
  @default_session_id "test_session"

  describe "build_messages/1" do
    test "builds messages with system prompt and conversation history" do
      config = %Config{
        name: @default_name,
        llm_options: @default_llm_options,
        system_prompt: "System prompt."
      }

      state = %State{
        session_id: @default_session_id,
        config: config,
        conversation_history: [
          %{role: "user", content: "Hello"},
          %{role: "assistant", content: "Hi!"}
        ]
      }

      {:ok, messages} = LangchainPromptBuilder.build_messages(state)
      assert length(messages) == 3
      [system_message | rest] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
      assert Enum.map(rest, & &1.role) == ["user", "assistant"]
    end

    test "builds messages without system prompt" do
      config = %Config{
        name: @default_name,
        llm_options: @default_llm_options,
        system_prompt: nil
      }

      state = %State{
        session_id: @default_session_id,
        config: config,
        conversation_history: [
          %{role: "user", content: "Hello"}
        ]
      }

      {:ok, messages} = LangchainPromptBuilder.build_messages(state)
      assert length(messages) == 1
      [user_message] = messages
      assert user_message.role == "user"
      assert user_message.content == "Hello"
    end

    test "handles empty conversation history" do
      config = %Config{
        name: @default_name,
        llm_options: @default_llm_options,
        system_prompt: "System prompt."
      }

      state = %State{
        session_id: @default_session_id,
        config: config,
        conversation_history: []
      }

      {:ok, messages} = LangchainPromptBuilder.build_messages(state)
      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
    end
  end
end
