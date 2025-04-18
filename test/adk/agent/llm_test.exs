defmodule Adk.Agent.LLMTest do
  use ExUnit.Case, async: false

  # Use fully qualified name instead of alias
  # alias Adk.Agent
  alias Adk.Agent.LLM
  alias Adk.Agent.Server

  # Mock LLM Provider Setup
  defmodule MockLLMProvider do
    use GenServer

    def start_link(_opts \\ []) do
      GenServer.start_link(__MODULE__, nil, name: __MODULE__)
    end

    def init(_) do
      {:ok, nil}
    end

    def chat(_messages, _opts) do
      GenServer.call(__MODULE__, :get_response)
    end

    def set_response(response) do
      GenServer.call(__MODULE__, {:update, response})
    end

    def handle_call(:get_response, _from, state) do
      {:reply, state, state}
    end

    def handle_call({:update, response}, _from, _state) do
      {:reply, :ok, response}
    end
  end

  defmodule TestTool do
    @behaviour Adk.Tool
    def definition, do: spec()

    def spec,
      do: %{
        name: "test_tool",
        description: "Test tool",
        parameters: %{type: "object", properties: %{input: %{type: "string"}}}
      }

    def execute(%{"input" => input}, _context), do: {:ok, "Processed: #{input}"}
  end

  # Custom prompt builder for testing
  defmodule TestPromptBuilder do
    @behaviour Adk.Agent.Llm.PromptBuilder

    @impl true
    def build_messages(%{input: input}) do
      messages = [
        %{role: "system", content: "Test system prompt"},
        %{role: "user", content: "Test user input: #{input}"}
      ]

      {:ok, messages}
    end

    def build_messages(_) do
      {:error, :invalid_context}
    end
  end

  setup do
    # Start the mock LLM provider as a GenServer
    start_supervised!(MockLLMProvider)

    # Unregister first in case it was already registered in a previous test
    Adk.ToolRegistry.unregister(:test_tool)

    # Register the test tool using correct function signature
    :ok = Adk.ToolRegistry.register(:test_tool, TestTool)
    :ok
  end

  # Teardown to stop the mock agent
  # teardown do
  #   :ok # Agent stops automatically on test process exit if linked
  # end

  describe "LLM.run/2 (direct struct execution)" do
    test "processes input and executes tool calls" do
      config = %{
        name: :llm_test,
        # Use spec from module
        tools: [TestTool.spec()],
        llm_provider: MockLLMProvider,
        # Ensure this exists
        prompt_builder: Adk.Agent.Llm.PromptBuilder.Default
      }

      {:ok, agent_struct} = LLM.new(config)

      # Set mock LLM response to request a tool call
      MockLLMProvider.set_response(
        {:ok,
         %{
           content: nil,
           tool_calls: [%{id: "call_123", name: "test_tool", args: %{"input" => "from_llm"}}]
         }}
      )

      {:ok, result} = LLM.run(agent_struct, "Can you process this for me?")

      # Assert that the tool was called and its result is included
      assert result.content == nil

      assert result.tool_calls == [
               %{id: "call_123", name: "test_tool", args: %{"input" => "from_llm"}}
             ]

      assert result.tool_results == [
               %{
                 tool_call_id: "call_123",
                 name: "test_tool",
                 content: "Processed: from_llm",
                 status: :ok
               }
             ]

      assert result.status == :tool_results_returned
    end

    test "handles direct responses without tool calls" do
      config = %{
        name: :llm_direct_test,
        tools: [TestTool.spec()],
        llm_provider: MockLLMProvider,
        prompt_builder: Adk.Agent.Llm.PromptBuilder.Default
      }

      {:ok, agent_struct} = LLM.new(config)

      # Set mock response - direct answer
      direct_answer = "I can answer this directly."
      MockLLMProvider.set_response({:ok, %{content: direct_answer, tool_calls: []}})

      {:ok, result} = LLM.run(agent_struct, "What's 2+2?")

      assert result.content == direct_answer
      assert result.tool_calls == []
      # tool_results might be nil or not present at all
      assert not Map.has_key?(result, :tool_results) || result.tool_results == nil
      assert result.status == :completed
    end

    test "llm provider returns an error" do
      config = %{name: :llm_error_test, llm_provider: MockLLMProvider}
      {:ok, agent_struct} = LLM.new(config)

      MockLLMProvider.set_response({:error, :provider_failed})

      assert {:error, :provider_failed} =
               LLM.run(agent_struct, "trigger error")
    end

    test "tool execution fails" do
      config = %{
        name: :llm_tool_fail_test,
        # Include spec for formatting
        tools: [%{name: "failing_tool", description: "x", parameters: %{}}],
        llm_provider: MockLLMProvider,
        prompt_builder: Adk.Agent.Llm.PromptBuilder.Default
      }

      {:ok, agent_struct} = LLM.new(config)

      # Set mock response to call a tool that will fail (not registered)
      MockLLMProvider.set_response(
        {:ok,
         %{
           content: nil,
           tool_calls: [%{id: "call_fail", name: "failing_tool", args: %{}}]
         }}
      )

      {:ok, result} = LLM.run(agent_struct, "fail tool call")

      # Assert the result shows the tool failure
      assert result.tool_results == [
               %{
                 tool_call_id: "call_fail",
                 name: "failing_tool",
                 content:
                   ~s(Error executing tool 'failing_tool': {:tool_not_found, :failing_tool}),
                 status: :error
               }
             ]

      assert result.status == :tool_results_returned
    end

    test "uses custom prompt builder" do
      config = %{
        name: :llm_custom_prompt_test,
        llm_provider: MockLLMProvider,
        prompt_builder: TestPromptBuilder
      }

      {:ok, agent_struct} = LLM.new(config)

      # Set the expected response
      MockLLMProvider.set_response(
        {:ok, %{content: "Custom prompt builder response", tool_calls: []}}
      )

      {:ok, result} = LLM.run(agent_struct, "Test input for custom prompt")

      assert result.content == "Custom prompt builder response"
      assert result.status == :completed
    end
  end

  describe "LLM via Agent.Server" do
    # Basic server execution test
    test "executes via server" do
      config = %{
        name: :llm_server_test,
        llm_provider: MockLLMProvider,
        prompt_builder: Adk.Agent.Llm.PromptBuilder.Default
      }

      {:ok, agent_struct} = LLM.new(config)

      direct_answer = "Server handled this."
      MockLLMProvider.set_response({:ok, %{content: direct_answer, tool_calls: []}})

      {:ok, pid} = Server.start_link(agent_struct)
      {:ok, result} = Server.run(pid, "server call")

      assert result.content == direct_answer
      assert result.status == :completed
    end

    # Test memory interaction (requires mock memory or setup)
    # test "uses memory history when run via server" do
    #   # ... setup mock memory ...
    #   # Add initial message to memory
    #   # Call Server.run
    #   # Assert mock LLM provider received messages including history
    # end
  end

  describe "config validation" do
    test "rejects missing required keys" do
      invalid_config = %{
        # Missing name
        llm_provider: MockLLMProvider
      }

      assert {:error, {:invalid_config, :missing_keys, keys}} = LLM.new(invalid_config)
      assert :name in keys
    end

    test "rejects invalid llm_provider" do
      # Non-module provider
      invalid_config = %{
        name: :invalid_provider_test,
        llm_provider: "not_a_module"
      }

      assert {:error, {:invalid_config, :invalid_llm_provider_type, "not_a_module"}} =
               LLM.new(invalid_config)

      # Module without chat/2 function
      invalid_module_config = %{
        name: :invalid_module_test,
        llm_provider: Enum
      }

      assert {:error, {:invalid_config, :llm_provider_missing_chat, Enum}} =
               LLM.new(invalid_module_config)
    end

    test "rejects invalid tools format" do
      invalid_config = %{
        name: :invalid_tools_test,
        llm_provider: MockLLMProvider,
        tools: "not a list"
      }

      assert {:error, {:invalid_config, :invalid_tools_type, "not a list"}} =
               LLM.new(invalid_config)
    end

    test "rejects invalid prompt builder" do
      # Non-module prompt builder
      invalid_config = %{
        name: :invalid_builder_test,
        llm_provider: MockLLMProvider,
        prompt_builder: "not_a_module"
      }

      assert {:error, {:invalid_config, :invalid_prompt_builder_type, "not_a_module"}} =
               LLM.new(invalid_config)

      # Module without build_messages/1 function
      invalid_module_config = %{
        name: :invalid_builder_module_test,
        llm_provider: MockLLMProvider,
        prompt_builder: Enum
      }

      assert {:error, tuple} = LLM.new(invalid_module_config)
      assert match?({:invalid_config, :invalid_prompt_builder, {Enum, :build_messages, 1}}, tuple)
    end

    test "applies default values" do
      minimal_config = %{
        name: :minimal_config_test,
        llm_provider: MockLLMProvider
      }

      {:ok, agent_struct} = LLM.new(minimal_config)

      # Check defaults were applied
      assert agent_struct.tools == []
      assert agent_struct.system_prompt == "You are a helpful assistant."
      assert agent_struct.prompt_builder == Adk.Agent.Llm.PromptBuilder.Default
      assert agent_struct.backend == Adk.Agent.LLM.LangchainBackend
      assert agent_struct.llm_options == %{}
    end
  end

  describe "start_link function" do
    test "delegates to Agent.Server.start_link with valid config" do
      config = %{
        name: :start_link_test,
        llm_provider: MockLLMProvider
      }

      {:ok, pid} = LLM.start_link(config)
      assert is_pid(pid)

      # Verify it's running as a GenServer
      assert Process.alive?(pid)
    end

    test "propagates errors from invalid config" do
      invalid_config = %{
        # Missing required name
        llm_provider: MockLLMProvider,
        prompt_builder: "invalid"
      }

      assert {:error, {:invalid_config, _, _}} = LLM.start_link(invalid_config)
    end
  end
end
