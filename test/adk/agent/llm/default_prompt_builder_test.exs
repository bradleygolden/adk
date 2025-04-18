defmodule Adk.Agent.Llm.PromptBuilder.DefaultTest do
  use ExUnit.Case

  alias Adk.Agent.Llm.PromptBuilder.Default
  alias Adk.Agent.LLM

  defmodule DummyProvider do
    @behaviour Adk.LLM.Provider
    def chat(_messages, _opts), do: {:ok, %{content: "dummy"}}
    def complete(_prompt, _opts), do: {:ok, "dummy completion"}
    def config, do: %{}
  end

  @default_provider DummyProvider

  describe "build_messages/1" do
    test "builds messages with system prompt, history, and input" do
      config = %LLM{
        model: @default_provider,
        system_prompt: "System prompt."
      }

      history = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi!"}
      ]

      input = "How are you?"

      context = %{config: config, history: history, input: input}

      {:ok, messages} = Default.build_messages(context)

      assert length(messages) == 4
      [system_message, user_msg1, assistant_msg, user_msg2] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
      assert user_msg1.role == "user" and user_msg1.content == "Hello"
      assert assistant_msg.role == "assistant" and assistant_msg.content == "Hi!"
      assert user_msg2.role == "user" and user_msg2.content == "How are you?"
    end

    test "builds messages without system prompt" do
      config = %LLM{
        model: @default_provider,
        system_prompt: nil
      }

      history = [
        %{role: "user", content: "Hello"}
      ]

      input = "World"

      context = %{config: config, history: history, input: input}

      {:ok, messages} = Default.build_messages(context)

      assert length(messages) == 2
      [user_msg1, user_msg2] = messages
      assert user_msg1.role == "user" and user_msg1.content == "Hello"
      assert user_msg2.role == "user" and user_msg2.content == "World"
    end

    test "handles empty conversation history" do
      config = %LLM{
        model: @default_provider,
        system_prompt: "System prompt."
      }

      history = []
      input = "First message"

      context = %{config: config, history: history, input: input}

      {:ok, messages} = Default.build_messages(context)

      assert length(messages) == 2
      [system_message, user_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
      assert user_message.role == "user" and user_message.content == "First message"
    end

    test "returns error for invalid context map" do
      invalid_context = %{config: nil}

      assert {:error, {:invalid_prompt_context, ^invalid_context}} =
               Default.build_messages(invalid_context)
    end
  end
end
