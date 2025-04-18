defmodule Adk.Agent.Llm.PromptBuilder.LangchainTest do
  use ExUnit.Case, async: true

  alias Adk.Agent.Llm.PromptBuilder.Langchain

  defmodule DummyProvider do
    @behaviour Adk.LLM.Provider
    def chat(_messages, _opts), do: {:ok, %{content: "dummy"}}
    def complete(_prompt, _opts), do: {:ok, "dummy completion"}
    def config, do: %{}
  end

  defmodule TestOutputSchema do
    defstruct [:result]

    def field_descriptions do
      %{
        result: "The result of the operation"
      }
    end
  end

  @default_provider DummyProvider

  describe "direct test of build_from_context" do
    test "with system prompt and output schema" do
      state = %{
        config: %{
          system_prompt: "System prompt.",
          output_schema: TestOutputSchema
        },
        history: [
          %{role: "user", content: "Hello"},
          %{role: "assistant", content: "Hi!"}
        ],
        input: "How are you?"
      }

      {:ok, messages} = Langchain.test_build_from_context(state)

      assert length(messages) == 4
      [system_message, user_msg, assistant_msg, last_user_msg] = messages
      assert system_message.role == "system"
      assert system_message.content =~ "System prompt."
      assert system_message.content =~ "RESPONSE FORMAT"
      assert user_msg.role == "user" and user_msg.content == "Hello"
      assert assistant_msg.role == "assistant" and assistant_msg.content == "Hi!"
      assert last_user_msg.role == "user" and last_user_msg.content == "How are you?"
    end

    test "with system prompt without output schema" do
      state = %{
        config: %{
          system_prompt: "System prompt."
        },
        history: [
          %{role: "user", content: "Hello"},
          %{role: "assistant", content: "Hi!"}
        ],
        input: "How are you?"
      }

      {:ok, messages} = Langchain.test_build_from_context(state)

      assert length(messages) == 4
      [system_message, user_msg, assistant_msg, last_user_msg] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
      assert user_msg.role == "user" and user_msg.content == "Hello"
      assert assistant_msg.role == "assistant" and assistant_msg.content == "Hi!"
      assert last_user_msg.role == "user" and last_user_msg.content == "How are you?"
    end

    test "without system prompt" do
      state = %{
        config: %{
          system_prompt: nil
        },
        history: [
          %{role: "user", content: "Hello"}
        ],
        input: "World"
      }

      {:ok, messages} = Langchain.test_build_from_context(state)

      assert length(messages) == 2
      [user_msg, last_user_msg] = messages
      assert user_msg.role == "user" and user_msg.content == "Hello"
      assert last_user_msg.role == "user" and last_user_msg.content == "World"
    end

    test "with null history" do
      state = %{
        config: %{
          system_prompt: "System prompt."
        },
        history: nil,
        input: "First message"
      }

      {:ok, messages} = Langchain.test_build_from_context(state)

      assert length(messages) == 2
      [system_message, user_msg] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
      assert user_msg.role == "user" and user_msg.content == "First message"
    end

    test "with empty history" do
      state = %{
        config: %{
          system_prompt: "System prompt."
        },
        history: [],
        input: "First message"
      }

      {:ok, messages} = Langchain.test_build_from_context(state)

      assert length(messages) == 2
      [system_message, user_msg] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
      assert user_msg.role == "user" and user_msg.content == "First message"
    end

    test "with no input" do
      state = %{
        config: %{
          system_prompt: "System prompt."
        },
        history: [
          %{role: "user", content: "Hello"}
        ],
        input: nil
      }

      {:ok, messages} = Langchain.test_build_from_context(state)

      assert length(messages) == 2
      [system_message, user_msg] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
      assert user_msg.role == "user" and user_msg.content == "Hello"
    end

    test "with nil system prompt and empty history and nil input" do
      state = %{
        config: %{
          system_prompt: nil
        },
        history: [],
        input: nil
      }

      {:ok, messages} = Langchain.test_build_from_context(state)

      assert Enum.empty?(messages)
    end
  end

  describe "build_messages/1 when hitting second branch" do
    test "explicit pattern match and function clause error with invalid state" do
      # This should trigger the second path in cond but fail in build_from_context
      state = %{
        history: [%{role: "user", content: "Hello"}],
        input: "World"
      }

      # We expect an error because this doesn't match the function clause
      assert_raise FunctionClauseError, fn ->
        Langchain.build_messages(state)
      end
    end

    test "invalid state format returns error" do
      invalid_state = %{not_valid: true}

      assert {:error, {:invalid_state_format, ^invalid_state}} =
               Langchain.build_messages(invalid_state)
    end
  end

  describe "build_messages/1 with llm state" do
    test "llm state with conversation history" do
      config = %{system_prompt: "System prompt."}

      conversation_history = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi!"}
      ]

      state = %{config: config, conversation_history: conversation_history}

      {:ok, messages} = Langchain.build_messages(state)

      assert length(messages) == 3
      [system_message, user_msg, assistant_msg] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
      assert user_msg.role == "user" and user_msg.content == "Hello"
      assert assistant_msg.role == "assistant" and assistant_msg.content == "Hi!"
    end

    test "llm state with output schema" do
      config = %{
        system_prompt: "System prompt.",
        output_schema: TestOutputSchema
      }

      conversation_history = []

      state = %{config: config, conversation_history: conversation_history}

      {:ok, messages} = Langchain.build_messages(state)

      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content =~ "System prompt."
      assert system_message.content =~ "RESPONSE FORMAT"
    end

    test "llm state without system prompt" do
      config = %{system_prompt: nil}

      conversation_history = [
        %{role: "user", content: "Hello"}
      ]

      state = %{config: config, conversation_history: conversation_history}

      {:ok, messages} = Langchain.build_messages(state)

      assert length(messages) == 1
      [user_msg] = messages
      assert user_msg.role == "user" and user_msg.content == "Hello"
    end

    test "llm state with null conversation history" do
      config = %{system_prompt: "System prompt."}

      conversation_history = nil

      state = %{config: config, conversation_history: conversation_history}

      {:ok, messages} = Langchain.build_messages(state)

      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
    end

    test "llm state with empty conversation history" do
      config = %{system_prompt: "System prompt."}

      conversation_history = []

      state = %{config: config, conversation_history: conversation_history}

      {:ok, messages} = Langchain.build_messages(state)

      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
    end

    test "llm state with nil system prompt and empty conversation history" do
      config = %{system_prompt: nil}

      conversation_history = []

      state = %{config: config, conversation_history: conversation_history}

      {:ok, messages} = Langchain.build_messages(state)

      assert Enum.empty?(messages)
    end
  end

  describe "build_messages/1 with enhanced context combinations" do
    test "context with system prompt and output schema" do
      config = %{
        model: @default_provider,
        system_prompt: "System prompt.",
        output_schema: TestOutputSchema
      }

      history = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi!"}
      ]

      input = "How are you?"

      context = %{config: config, history: history, input: input}

      {:ok, messages} = Langchain.build_messages(context)

      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content =~ "System prompt."
      assert system_message.content =~ "RESPONSE FORMAT"
      assert system_message.content =~ "result"
    end

    test "context with system prompt without output schema" do
      config = %{
        model: @default_provider,
        system_prompt: "System prompt."
      }

      history = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi!"}
      ]

      input = "How are you?"

      context = %{config: config, history: history, input: input}

      {:ok, messages} = Langchain.build_messages(context)

      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
    end

    test "context without system prompt" do
      config = %{
        model: @default_provider,
        system_prompt: nil
      }

      history = [
        %{role: "user", content: "Hello"}
      ]

      input = "World"

      context = %{config: config, history: history, input: input}

      {:ok, messages} = Langchain.build_messages(context)

      assert Enum.empty?(messages)
    end

    test "context with null history" do
      config = %{
        model: @default_provider,
        system_prompt: "System prompt."
      }

      history = nil
      input = "First message"

      context = %{config: config, history: history, input: input}

      {:ok, messages} = Langchain.build_messages(context)

      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
    end

    test "context with empty history" do
      config = %{
        model: @default_provider,
        system_prompt: "System prompt."
      }

      history = []
      input = "First message"

      context = %{config: config, history: history, input: input}

      {:ok, messages} = Langchain.build_messages(context)

      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
    end

    test "context with no input" do
      config = %{
        model: @default_provider,
        system_prompt: "System prompt."
      }

      history = [
        %{role: "user", content: "Hello"}
      ]

      input = nil

      context = %{config: config, history: history, input: input}

      {:ok, messages} = Langchain.build_messages(context)

      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
    end

    test "context with nil system prompt and empty history and nil input" do
      config = %{
        model: @default_provider,
        system_prompt: nil
      }

      history = []
      input = nil

      context = %{config: config, history: history, input: input}

      {:ok, messages} = Langchain.build_messages(context)

      assert Enum.empty?(messages)
    end
  end

  describe "build_from_context edge cases" do
    test "with empty input and system prompt but non-empty history" do
      state = %{
        config: %{
          system_prompt: "System prompt."
        },
        history: [
          %{role: "user", content: "Hello"},
          %{role: "assistant", content: "Hi!"}
        ],
        input: ""
      }

      {:ok, messages} = Langchain.test_build_from_context(state)

      assert length(messages) == 4
      [system_message, user_msg, assistant_msg, last_user_msg] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
      assert user_msg.role == "user" and user_msg.content == "Hello"
      assert assistant_msg.role == "assistant" and assistant_msg.content == "Hi!"
      assert last_user_msg.role == "user" and last_user_msg.content == ""
    end

    test "with nil input and nil history but with system prompt" do
      state = %{
        config: %{
          system_prompt: "System prompt."
        },
        history: nil,
        input: nil
      }

      {:ok, messages} = Langchain.test_build_from_context(state)

      assert length(messages) == 1
      [system_message] = messages
      assert system_message.role == "system"
      assert system_message.content == "System prompt."
    end

    test "with complex output schema in config" do
      defmodule ComplexOutputSchema do
        defstruct [:result, :confidence, :reasoning]

        def field_descriptions do
          %{
            result: "The final result",
            confidence: "Confidence score between 0 and 1",
            reasoning: "Reasoning process to reach the result"
          }
        end
      end

      state = %{
        config: %{
          system_prompt: "Do a complex analysis.",
          output_schema: ComplexOutputSchema
        },
        history: [],
        input: "Analyze this."
      }

      {:ok, messages} = Langchain.test_build_from_context(state)

      assert length(messages) == 2
      [system_message, user_msg] = messages
      assert system_message.role == "system"
      assert system_message.content =~ "Do a complex analysis."
      assert system_message.content =~ "RESPONSE FORMAT"
      assert system_message.content =~ "result"
      assert system_message.content =~ "confidence"
      assert system_message.content =~ "reasoning"
      assert user_msg.role == "user"
      assert user_msg.content == "Analyze this."
    end
  end
end
