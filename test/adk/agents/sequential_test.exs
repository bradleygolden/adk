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

    test "returns error if a step fails" do
      agent_config = %{
        name: :sequential_error_test,
        steps: [
          %{
            type: "function",
            function: fn _input -> {:error, :step_failed} end
          },
          %{
            type: "function",
            function: fn input -> "Should not run: #{input}" end
          }
        ]
      }

      {:ok, agent} = Adk.create_agent(:sequential, agent_config)
      result = Adk.run(agent, "irrelevant input")

      assert {:error,
              {:step_execution_error, :function, _,
               %Protocol.UndefinedError{protocol: String.Chars, value: {:error, :step_failed}}}} =
               result
    end

    test "handles empty input" do
      agent_config = %{
        name: :sequential_empty_input_test,
        steps: [
          %{
            type: "function",
            function: fn input -> input end
          }
        ]
      }

      {:ok, agent} = Adk.create_agent(:sequential, agent_config)
      {:ok, result} = Adk.run(agent, "")
      assert result.output == ""
    end

    test "returns error if a step times out" do
      agent_config = %{
        name: :sequential_timeout_test,
        steps: [
          %{
            type: "function",
            function: fn _input ->
              # Simulate a long-running step
              :timer.sleep(200)
              "done"
            end
          }
        ]
      }

      {:ok, agent} = Adk.create_agent(:sequential, agent_config)
      # Run with a short timeout to simulate timeout error
      exit = catch_exit(GenServer.call(agent, {:run, "input"}, 50))
      assert match?({:timeout, {GenServer, :call, [_pid, {:run, "input"}, 50]}}, exit)
    end
  end
end
