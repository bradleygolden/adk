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

    test "returns error if a task fails" do
      agent_config = %{
        name: :parallel_error_test,
        tasks: [
          %{
            type: "function",
            function: fn _input -> {:error, :task_failed} end
          },
          %{
            type: "function",
            function: fn _input -> "Should not run" end
          }
        ]
      }

      {:ok, agent} = Adk.create_agent(:parallel, agent_config)
      {:ok, result} = Adk.run(agent, "irrelevant input")
      assert result.output[0] == {:error, :task_failed}
      assert result.output[1] == "Should not run"
      assert String.contains?(result.combined, "{:error, :task_failed}")
      assert String.contains?(result.combined, "Should not run")
    end

    test "returns error if a task times out" do
      agent_config = %{
        name: :parallel_timeout_test,
        tasks: [
          %{
            type: "function",
            function: fn _input ->
              :timer.sleep(200)
              "done"
            end
          }
        ]
      }

      {:ok, agent} = Adk.create_agent(:parallel, agent_config)
      exit = catch_exit(GenServer.call(agent, {:run, "input"}, 50))
      assert match?({:timeout, {GenServer, :call, [_pid, {:run, "input"}, 50]}}, exit)
    end

    test "returns empty map if no tasks are provided" do
      agent_config = %{
        name: :parallel_empty_test,
        tasks: []
      }

      {:ok, agent} = Adk.create_agent(:parallel, agent_config)
      {:ok, result} = Adk.run(agent, "any input")
      assert result.output == %{}
      assert result.combined == ""
    end
  end
end
