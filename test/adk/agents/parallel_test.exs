defmodule Adk.Agents.ParallelTest do
  use ExUnit.Case, async: true

  setup do
    # Only register the test tool; registries and supervisors are started by the application
    Adk.register_tool(Adk.AgentsTest.TestTool)
    :ok
  end

  describe "parallel execution" do
    test "executes tasks in parallel" do
      agent_config = %{
        name: :parallel_test,
        tasks: [
          %{
            type: "function",
            function: fn _input -> "Task 1 result" end
          },
          %{
            type: "function",
            function: fn _input -> "Task 2 result" end
          },
          %{
            type: "tool",
            tool: "test_tool",
            params: %{"input" => "from_task_3"}
          }
        ]
      }

      {:ok, agent} = Adk.create_agent(:parallel, agent_config)
      {:ok, result} = Adk.run(agent, "test input")

      assert Map.has_key?(result.output, 0)
      assert Map.has_key?(result.output, 1)
      assert Map.has_key?(result.output, 2)
      assert result.output[0] == "Task 1 result"
      assert result.output[1] == "Task 2 result"
      assert result.output[2] == "Processed: from_task_3"
      assert String.contains?(result.combined, "Task 1 result")
      assert String.contains?(result.combined, "Task 2 result")
      assert String.contains?(result.combined, "Processed: from_task_3")
    end
  end
end
