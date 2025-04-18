defmodule AdkTest do
  use ExUnit.Case

  setup do
    on_exit(fn ->
      # Clean up after tests
      :ok = Adk.ToolRegistry.unregister(:executable_tool)

      # Remove configuration
      Application.delete_env(:adk, :mock_provider)
      Application.delete_env(:adk, :llm_provider)
    end)

    :ok
  end

  describe "version/0" do
    test "returns a version string" do
      assert Adk.version() == "0.1.0"
    end
  end

  describe "create_agent/2" do
    test "creates a sequential agent" do
      config = %{
        name: :test_seq,
        steps: [
          %{type: "function", function: fn _input -> "test output" end}
        ]
      }

      {:ok, agent} = Adk.create_agent(:sequential, config)
      assert is_pid(agent)
    end

    test "creates a loop agent" do
      config = %{
        name: :test_loop,
        steps: [
          %{type: "function", function: fn input -> "#{input} processed" end}
        ],
        condition: fn _output, _memory -> true end
      }

      {:ok, agent} = Adk.create_agent(:loop, config)
      assert is_pid(agent)
    end

    test "returns error for invalid config" do
      invalid_config = %{name: :invalid_agent}
      assert {:error, _reason} = Adk.create_agent(:sequential, invalid_config)
    end
  end

  describe "run/2" do
    test "runs agent with pid" do
      config = %{
        name: :test_run,
        steps: [
          %{type: "function", function: fn _input -> "test output" end}
        ]
      }

      {:ok, agent} = Adk.create_agent(:sequential, config)
      assert {:ok, %{output: "test output"}} = Adk.run(agent, "input")
    end

    test "runs agent with struct" do
      config = %{
        name: :test_run_struct,
        steps: [%{type: "function", function: fn _input -> "output from struct" end}]
      }

      {:ok, agent_struct} = Adk.Agent.Sequential.new(config)
      assert {:ok, %{output: "output from struct"}} = Adk.run(agent_struct, "input")
    end

    test "returns error for invalid agent" do
      assert {:error, {:invalid_agent, _}} = Adk.run("not an agent", "input")
    end
  end

  describe "tool registry operations" do
    # Define test tool outside of the test
    defmodule ToolRegistryTestTool do
      @behaviour Adk.Tool

      @impl true
      def definition do
        %{
          name: "executable_tool",
          description: "Tool for execution test",
          parameters: %{
            type: "object",
            properties: %{
              param: %{type: "string", description: "Parameter"}
            }
          }
        }
      end

      @impl true
      def execute(%{"param" => value}, _context) do
        {:ok, "Executed with: #{value}"}
      end
    end

    test "registers and executes tools" do
      # Register tool
      :ok = Adk.register_tool(ToolRegistryTestTool)

      # List tools should include our test tool
      tools = Adk.list_tools()
      assert Enum.any?(tools, fn tool -> tool == ToolRegistryTestTool end)

      # Execute the tool
      assert {:ok, "Executed with: test"} =
               Adk.execute_tool(:executable_tool, %{"param" => "test"})
    end
  end

  describe "LLM integration" do
    test "complete/3 and chat/3 call the LLM provider" do
      # Define a mock LLM provider
      defmodule MockLLMProvider do
        def complete(_prompt, _opts) do
          {:ok, "Mock completion response"}
        end

        def chat(_messages, _opts) do
          {:ok, %{content: "Mock chat response", tool_calls: []}}
        end
      end

      # Configure the mock provider directly in the LLM module
      original_provider = Application.get_env(:adk, :llm_provider)

      # Setup
      Application.put_env(:adk, :llm_provider, MockLLMProvider)

      try do
        # Test completion with provider explicitly specified
        assert {:ok, "Mock completion response"} =
                 Adk.LLM.complete(MockLLMProvider, "Test prompt")

        # Test chat with provider explicitly specified
        messages = [%{role: "user", content: "Test message"}]

        assert {:ok, %{content: "Mock chat response"}} =
                 Adk.LLM.chat(MockLLMProvider, messages)
      after
        # Restore the original provider
        if original_provider do
          Application.put_env(:adk, :llm_provider, original_provider)
        else
          Application.delete_env(:adk, :llm_provider)
        end
      end
    end
  end

  describe "Memory integration" do
    test "memory operations" do
      # Setup
      session_id = "memory_test_session_#{:rand.uniform(1000)}"
      test_data = %{initial_data: "test memory data"}

      # Add to memory
      assert :ok = Adk.add_to_memory(:in_memory, session_id, test_data)

      # Test get
      {:ok, result} = Adk.get_memory(:in_memory, session_id)
      assert is_map(result)

      # Test search
      {:ok, search_result} = Adk.search_memory(:in_memory, session_id, "test")
      assert is_list(search_result) || is_map(search_result)

      # Test clear
      assert :ok = Adk.clear_memory(:in_memory, session_id)
    end
  end
end
