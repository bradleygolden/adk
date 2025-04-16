defmodule Adk.Agents.LoopTest do
  use ExUnit.Case, async: true

  setup do
    # Only register the test tool; registries and supervisors are started by the application
    Adk.register_tool(Adk.AgentsTest.TestTool)
    :ok
  end

  describe "loop execution" do
    test "repeats steps until condition is met" do
      agent_config = %{
        name: :loop_test,
        steps: [
          %{
            type: "function",
            function: fn input ->
              # Parse the count from input (default to 0)
              count =
                case Integer.parse(input) do
                  {n, _} -> n
                  :error -> 0
                end

              # Increment the count
              "#{count + 1}"
            end
          }
        ],
        # Stop when we reach 5
        condition: fn output, _memory ->
          case Integer.parse(output) do
            {n, _} -> n >= 5
            :error -> false
          end
        end,
        max_iterations: 10
      }

      {:ok, agent} = Adk.create_agent(:loop, agent_config)
      {:ok, result} = Adk.run(agent, "0")

      assert result.output == "5"
      assert result.status == :condition_met
    end

    test "stops at max iterations if condition is never met" do
      agent_config = %{
        name: :loop_max_test,
        steps: [
          %{
            type: "function",
            function: fn input ->
              # Parse the count from input (default to 0)
              count =
                case Integer.parse(input) do
                  {n, _} -> n
                  :error -> 0
                end

              # Increment the count
              "#{count + 1}"
            end
          }
        ],
        # Never stop
        condition: fn _output, _memory -> false end,
        max_iterations: 3
      }

      {:ok, agent} = Adk.create_agent(:loop, agent_config)
      {:ok, result} = Adk.run(agent, "0")

      assert result.output == "3"
      assert result.status == :max_iterations_reached
    end
  end
end
