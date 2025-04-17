defmodule Adk.Agents.LangchainTest do
  use ExUnit.Case, async: false
  import Mox
  setup :set_mox_from_context
  setup :verify_on_exit!
  alias Adk.Test.Schemas.{}

  @moduletag :capture_log

  # Add a setup block to ensure mock expectations are properly set
  setup do
    # Allow calls to the mock modules across processes
    Mox.allow(Adk.LLM.Providers.OpenAIMock, self(), Process.whereis(Adk.AgentRegistry))
    Mox.allow(Adk.LLM.Providers.LangchainMock, self(), Process.whereis(Adk.AgentRegistry))

    # Set up default stubs for OpenAIMock
    Mox.stub(Adk.LLM.Providers.OpenAIMock, :chat, fn _messages, _opts ->
      {:ok, %{content: "Test response from OpenAI mock", tool_calls: nil}}
    end)

    Mox.stub(Adk.LLM.Providers.OpenAIMock, :complete, fn _prompt, _opts ->
      {:ok, "Test completion from OpenAI mock"}
    end)

    # Set up default stubs for LangchainMock
    Mox.stub(Adk.LLM.Providers.LangchainMock, :chat, fn _messages, _opts ->
      {:ok, %{content: "Test response from Langchain mock", tool_calls: nil}}
    end)

    Mox.stub(Adk.LLM.Providers.LangchainMock, :complete, fn _prompt, _opts ->
      {:ok, "Test completion from Langchain mock"}
    end)

    :ok
  end

  describe "agent supervisor start_agent/2" do
    test "starts a langchain agent and returns a pid" do
      config = %{
        name: :test_supervisor_langchain_agent,
        llm_options: %{
          provider: :openai,
          model: "gpt-3.5-turbo",
          api_key: "test-api-key"
        }
      }

      assert {:ok, pid} = Adk.AgentSupervisor.start_agent(:langchain, config)
      assert is_pid(pid)
      Process.exit(pid, :normal)
    end

    test "returns error for unknown agent type" do
      result = Adk.AgentSupervisor.get_agent_module(:not_a_real_type)
      assert {:error, {:agent_module_not_loaded, :not_a_real_type}} = result
    end

    test "returns error when starting two agents with the same name" do
      config = %{
        name: :duplicate_agent_name,
        llm_options: %{
          provider: :openai,
          model: "gpt-3.5-turbo",
          api_key: "test-api-key"
        }
      }

      assert {:ok, pid1} = Adk.AgentSupervisor.start_agent(:langchain, config)
      assert is_pid(pid1)
      # Attempt to start another agent with the same name
      assert {:error, {:already_started, _}} = Adk.AgentSupervisor.start_agent(:langchain, config)
      Process.exit(pid1, :normal)
    end

    defmodule CustomAgent do
      use GenServer
      def start_link(_), do: GenServer.start_link(__MODULE__, :ok, [])
      def init(:ok), do: {:ok, %{}}
    end

    test "can start a custom agent module" do
      config = %{}
      assert {:ok, pid} = Adk.AgentSupervisor.start_agent(CustomAgent, config)
      assert is_pid(pid)
      Process.exit(pid, :normal)
    end

    defp wait_for_registry(name, timeout_ms) do
      deadline = System.monotonic_time(:millisecond) + timeout_ms
      do_wait(name, deadline)
    end

    defp do_wait(name, deadline) do
      case Registry.lookup(Adk.AgentRegistry, name) do
        [{pid, _}] when is_pid(pid) ->
          pid

        _ ->
          if System.monotonic_time(:millisecond) < deadline do
            Process.sleep(10)
            do_wait(name, deadline)
          else
            nil
          end
      end
    end

    test "restarts agent if it crashes (one_for_one strategy)" do
      config = %{
        name: :restart_test_agent,
        llm_options: %{
          provider: :openai,
          model: "gpt-3.5-turbo",
          api_key: "test-api-key"
        }
      }

      assert {:ok, pid1} = Adk.AgentSupervisor.start_agent(:langchain, config)
      assert is_pid(pid1)
      ref = Process.monitor(pid1)
      # Simulate crash
      Process.exit(pid1, :kill)
      # Wait for DOWN message
      assert_receive {:DOWN, ^ref, :process, ^pid1, :killed}, 500

      # Wait for the agent to be registered again (up to 500ms)
      pid2 = wait_for_registry(:restart_test_agent, 500)
      assert is_pid(pid2)
      # The agent may or may not be restarted with a different PID,
      # depending on how the supervisor handles restarts
      Process.exit(pid2, :normal)
    end
  end

  describe "provider and supervisor integration" do
    test "langchain provider config has expected structure" do
      config = Adk.LLM.Providers.Langchain.config()
      assert config.name == "langchain"
      assert is_binary(config.description)
    end

    test "agent supervisor recognizes langchain agent type" do
      module = Adk.AgentSupervisor.get_agent_module(:langchain)
      assert module == Adk.Agents.Langchain
    end
  end

  describe "agent creation and configuration" do
    test "accepts valid configuration with openai provider" do
      valid_config = %{
        name: :test_langchain_agent_openai,
        llm_options: %{
          provider: :openai,
          model: "gpt-3.5-turbo",
          api_key: "test-api-key"
        }
      }

      assert {:ok, pid} = Adk.create_agent(:langchain, valid_config)
      assert is_pid(pid)

      # Clean up
      Process.exit(pid, :normal)
    end

    test "rejects configuration without llm_options" do
      invalid_config = %{
        name: :test_langchain_agent_invalid
      }

      assert {:error, {:invalid_config, :missing_keys, [:llm_options]}} =
               Adk.create_agent(:langchain, invalid_config)
    end

    test "rejects configuration with empty llm_options map" do
      invalid_config = %{
        name: :test_langchain_agent_empty_llm,
        llm_options: %{}
      }

      assert {:error,
              {:invalid_config, :missing_llm_option, "API key is required in llm_options"}} =
               Adk.create_agent(:langchain, invalid_config)
    end

    test "rejects configuration with nil llm_options" do
      invalid_config = %{
        name: :test_langchain_agent_nil_llm,
        llm_options: nil
      }

      assert {:error, {:invalid_config, :missing_llm_options}} =
               Adk.create_agent(:langchain, invalid_config)
    end

    test "rejects configuration with missing required fields" do
      # Missing api_key
      config1 = %{
        name: :test_langchain_agent_missing_api_key,
        llm_options: %{provider: :openai, model: "gpt-3.5-turbo"}
      }

      assert {:error,
              {:invalid_config, :missing_llm_option, "API key is required in llm_options"}} =
               Adk.create_agent(:langchain, config1)

      # Missing provider
      config2 = %{
        name: :test_langchain_agent_missing_provider,
        llm_options: %{api_key: "test-key", model: "gpt-3.5-turbo"}
      }

      assert {:error,
              {:invalid_config, :missing_llm_option,
               "Provider (:openai, :anthropic) is required in llm_options"}} =
               Adk.create_agent(:langchain, config2)

      # Missing model
      config3 = %{
        name: :test_langchain_agent_missing_model,
        llm_options: %{provider: :openai, api_key: "test-key"}
      }

      assert {:error, {:invalid_config, :missing_llm_option, "Model is required in llm_options"}} =
               Adk.create_agent(:langchain, config3)
    end
  end

  describe "API integration" do
    test "processes input with LangChain successfully" do
      config = %{
        name: "test_agent_api_success_run",
        llm_options: %{
          model: "gpt-3.5-turbo",
          temperature: 0.7,
          api_key: "dummy-key",
          provider: Adk.LLM.Providers.OpenAIMock
        }
      }

      # Use expect instead of stub for this specific test
      Mox.expect(Adk.LLM.Providers.OpenAIMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "Test response from OpenAI mock", tool_calls: nil}}
      end)

      {:ok, agent} = Adk.create_agent(:langchain, config)

      assert {:ok, %{output: %{output: "Test response from OpenAI mock", status: :completed}}} =
               Adk.run(agent, "Test input")
    end

    test "handles LangChain API errors" do
      config = %{
        name: "test_agent_api_error_run",
        llm_options: %{
          model: "gpt-3.5-turbo",
          temperature: 0.7,
          api_key: "dummy-key",
          provider: Adk.LLM.Providers.OpenAIMock
        }
      }

      # Simulate error by using expect instead of stub
      Mox.expect(Adk.LLM.Providers.OpenAIMock, :chat, fn _messages, _opts ->
        {:error, {:llm_provider_error, %LangChain.LangChainError{message: "API error occurred"}}}
      end)

      {:ok, agent} = Adk.create_agent(:langchain, config)

      # Match nested error structure
      assert {:error,
              {:llm_provider_error,
               {:llm_provider_error, %LangChain.LangChainError{message: msg}}}} =
               Adk.run(agent, "Test input")

      assert msg =~ "API error occurred"
    end

    test "handles connection errors to custom endpoint" do
      config = %{
        name: "test_agent_conn_error_run",
        llm_options: %{
          model: "gpt-3.5-turbo",
          api_key: "test_key",
          provider: Adk.LLM.Providers.OpenAIMock
        }
      }

      # Simulate connection error with expect
      Mox.expect(Adk.LLM.Providers.OpenAIMock, :chat, fn _messages, _opts ->
        {:error,
         {:llm_provider_error,
          "Failed to run LLMChain: %CaseClauseError{term: {:error, %Req.TransportError{reason: :econnrefused}}}"}}
      end)

      {:ok, agent} = Adk.create_agent(:langchain, config)
      result = Adk.run(agent, "Hello")
      assert match?({:error, {:llm_provider_error, _}}, result)
    end

    test "uses custom endpoint" do
      config = %{
        name: :test_custom_endpoint_behavior,
        llm_options: %{
          api_key: "test-key",
          provider: Adk.LLM.Providers.OpenAIMock,
          model: "gpt-3.5-turbo"
        }
      }

      # Test successful response - use expect instead of stub
      Mox.expect(Adk.LLM.Providers.OpenAIMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "Test response from OpenAI mock", tool_calls: nil}}
      end)

      {:ok, agent} = Adk.create_agent(:langchain, config)
      assert {:ok, result} = Adk.run(agent, "Test input")
      assert result.output.status == :completed
      assert result.output.output == "Test response from OpenAI mock"
    end

    test "handles invalid API key" do
      config = %{
        name: "test_agent_invalid_key_run",
        llm_options: %{
          api_key: "invalid_key",
          provider: Adk.LLM.Providers.OpenAIMock,
          model: "gpt-3.5-turbo"
        }
      }

      # Simulate invalid key error with expect
      Mox.expect(Adk.LLM.Providers.OpenAIMock, :chat, fn _messages, _opts ->
        {:error, {:llm_provider_error, %LangChain.LangChainError{message: "Invalid API key"}}}
      end)

      {:ok, agent} = Adk.create_agent(:langchain, config)

      # Match nested error structure
      assert {:error,
              {:llm_provider_error,
               {:llm_provider_error, %LangChain.LangChainError{message: error_message}}}} =
               Adk.run(agent, "Hello")

      assert error_message =~ "Invalid API key"
    end

    test "API integration validates output against output schema" do
      config = %{
        name: :test_schema_output_validation_api_block,
        llm_options: %{
          api_key: "test-key",
          provider: Adk.LLM.Providers.OpenAIMock,
          model: "gpt-3.5-turbo"
        },
        output_schema: Adk.Test.Schemas.OutputSchema
      }

      # Test valid output
      valid_output = %Adk.Test.Schemas.OutputSchema{answer: "It is sunny.", confidence: 0.8}

      Mox.expect(Adk.LLM.Providers.OpenAIMock, :chat, fn _messages, _opts ->
        {:ok, %{content: JSON.encode!(valid_output), tool_calls: nil}}
      end)

      {:ok, agent} = Adk.create_agent(:langchain, config)
      {:ok, result} = Adk.run(agent, "What's the weather?")
      assert result.output.status == :schema_validated
      assert result.output.output == valid_output
    end

    test "API integration processes input with LangChain successfully" do
      config = %{
        name: :test_langchain_input_processing,
        llm_options: %{
          api_key: "test-key",
          provider: Adk.LLM.Providers.OpenAIMock,
          model: "gpt-3.5-turbo"
        },
        input_schema: Adk.Test.Schemas.InputSchema
      }

      # Test with valid input
      valid_input = JSON.encode!(%{query: "What's the weather?", user_id: 123})

      Mox.expect(Adk.LLM.Providers.OpenAIMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "It is sunny today", tool_calls: nil}}
      end)

      {:ok, agent} = Adk.create_agent(:langchain, config)
      {:ok, result} = Adk.run(agent, valid_input)
      assert result.output.status == :completed
      assert result.output.output == "It is sunny today"
    end
  end

  describe "Tool Handling" do
    setup do
      case Adk.ToolRegistry.register(:test_tool, Adk.AgentsTest.TestTool) do
        :ok -> :ok
        {:error, :already_registered} -> :ok
        other -> other
      end

      case Adk.ToolRegistry.register(:error_tool, Adk.Agents.LangchainTest.ErrorTool) do
        :ok -> :ok
        {:error, :already_registered} -> :ok
        other -> other
      end

      :ok
    end

    defmodule ErrorTool do
      use Adk.Tool
      def definition, do: %{name: "error_tool", description: "", parameters: %{}}
      def execute(_params, _ctx), do: {:error, :fail}
    end

    test "executes a valid tool call and returns the result" do
      config = %{
        name: :test_tool_call_agent,
        llm_options: %{
          provider: Adk.LLM.Providers.LangchainMock,
          model: "gpt-3.5-turbo",
          api_key: "test-api-key"
        },
        tools: ["test_tool"]
      }

      tool_call = %{
        "id" => "call_1",
        "type" => "function",
        "function" => %{"name" => "test_tool", "arguments" => ~s({"input": "foo"})}
      }

      # Set up mock to return tool call for this specific test
      Mox.expect(Adk.LLM.Providers.LangchainMock, :chat, fn _messages, _opts ->
        {:ok, %{content: nil, tool_calls: [tool_call]}}
      end)

      {:ok, agent} = Adk.create_agent(:langchain, config)

      assert {:ok, %{output: %{output: "Processed: foo", status: :tool_call_completed}}} =
               Adk.run(agent, "trigger tool call")
    end

    test "handles malformed tool call structure gracefully" do
      config = %{
        name: :test_tool_call_agent_malformed,
        llm_options: %{
          provider: Adk.LLM.Providers.LangchainMock,
          model: "gpt-3.5-turbo",
          api_key: "test-api-key"
        },
        tools: ["test_tool"]
      }

      tool_call = %{"id" => "call_1", "type" => "function"}

      # Set up mock to return malformed tool call for this specific test
      Mox.expect(Adk.LLM.Providers.LangchainMock, :chat, fn _messages, _opts ->
        {:ok, %{content: nil, tool_calls: [tool_call]}}
      end)

      {:ok, agent} = Adk.create_agent(:langchain, config)

      assert {:ok,
              %{
                output: %{
                  output: "Error: Malformed tool call received from LLM",
                  status: :tool_call_completed
                }
              }} =
               Adk.run(agent, "trigger malformed tool call")
    end

    test "handles tool execution error gracefully" do
      config = %{
        name: :test_tool_call_agent_error,
        llm_options: %{
          provider: Adk.LLM.Providers.LangchainMock,
          model: "gpt-3.5-turbo",
          api_key: "test-api-key"
        },
        tools: ["error_tool"]
      }

      tool_call = %{
        "id" => "call_1",
        "type" => "function",
        "function" => %{"name" => "error_tool", "arguments" => ~s({})}
      }

      # Set up mock to return tool call for error tool
      Mox.expect(Adk.LLM.Providers.LangchainMock, :chat, fn _messages, _opts ->
        {:ok, %{content: nil, tool_calls: [tool_call]}}
      end)

      {:ok, agent} = Adk.create_agent(:langchain, config)

      assert {:ok,
              %{output: %{output: "Error executing tool: :fail", status: :tool_call_completed}}} =
               Adk.run(agent, "trigger error tool call")
    end
  end

  # describe "Tool Handling" do ... end # Future tests
end
