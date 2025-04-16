defmodule AdkTest do
  use ExUnit.Case

  defmodule TestTool do
    use Adk.Tool

    @impl true
    def definition do
      %{
        name: "test_tool",
        description: "A test tool for testing",
        parameters: %{
          input: %{
            type: "string",
            description: "The input to the tool"
          }
        }
      }
    end

    @impl Adk.Tool
    def execute(%{"input" => input}, _context) do
      {:ok, "Processed: #{input}"}
    end
  end

  setup do
    # Only register the test tool; registries and supervisors are started by the application
    Adk.register_tool(TestTool)
    :ok
  end

  test "creates and runs a sequential agent" do
    # Define a sequential agent with steps
    agent_config = %{
      name: :test_agent,
      steps: [
        %{
          type: "function",
          function: fn input -> "Step 1: #{input}" end
        },
        %{
          type: "function",
          function: fn input -> "Step 2: #{input}" end
        },
        %{
          type: "tool",
          tool: "test_tool",
          params: %{"input" => "from_tool"}
        }
      ]
    }

    # Create the agent
    {:ok, agent} = Adk.create_agent(:sequential, agent_config)

    # Run the agent
    {:ok, result} = Adk.run(agent, "test input")

    # Check the final output
    assert result.output == "Processed: from_tool"
  end

  test "tool registry functionality" do
    # Since we don't have control over other tests, we'll specifically look for our test tool
    tools = Adk.list_tools()
    assert Enum.any?(tools, fn module -> module == TestTool end)

    # Look up a tool
    {:ok, tool_module} = Adk.ToolRegistry.lookup(:test_tool)
    assert tool_module == TestTool

    # Try to look up a non-existent tool
    assert {:error, {:tool_not_found, :nonexistent_tool}} =
             Adk.ToolRegistry.lookup(:nonexistent_tool)
  end
end
