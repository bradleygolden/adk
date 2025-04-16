defmodule Adk.Agents.SequentialTest do
  use ExUnit.Case, async: true

  setup do
    # Only register the test tool; registries and supervisors are started by the application
    Adk.register_tool(Adk.AgentsTest.TestTool)
    :ok
  end

  describe "sequential execution" do
    test "executes steps in order" do
      agent_config = %{
        name: :sequential_test,
        steps: [
          %{
            type: "function",
            function: fn input -> "Step 1: #{input}" end
          },
          %{
            type: "function",
            function: fn input -> "Step 2: #{input}" end
          }
        ]
      }

      {:ok, agent} = Adk.create_agent(:sequential, agent_config)
      {:ok, result} = Adk.run(agent, "test input")

      assert result.output == "Step 2: Step 1: test input"
    end
  end
end
