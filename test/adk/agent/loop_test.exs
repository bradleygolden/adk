defmodule Adk.Agent.LoopTest do
  use ExUnit.Case, async: true

  setup do
    # Only register the test tool; registries and supervisors are started by the application
    Adk.register_tool(Adk.AgentTest.TestTool)
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

    test "executes tool step" do
      agent_config = %{
        name: :loop_tool_test,
        steps: [
          %{
            type: "tool",
            tool: "test_tool",
            params: %{"test_input" => "test value"}
          }
        ],
        condition: fn output, _memory -> output == "Processed test value" end,
        max_iterations: 5
      }

      {:ok, agent} = Adk.create_agent(:loop, agent_config)
      {:ok, result} = Adk.run(agent, "doesn't matter")

      assert result.output == "Processed test value"
      assert result.status == :condition_met
    end

    test "handles step error" do
      agent_config = %{
        name: :loop_error_test,
        steps: [
          %{
            type: "function",
            function: fn _input ->
              raise "Deliberate test error"
            end
          }
        ],
        condition: fn _output, _memory -> false end
      }

      {:ok, agent} = Adk.create_agent(:loop, agent_config)
      {:error, reason} = Adk.run(agent, "initial input")

      assert match?({:step_execution_error, :function, _, _}, reason)
    end

    test "handles condition error" do
      agent_config = %{
        name: :loop_condition_error_test,
        steps: [
          %{
            type: "function",
            function: fn input -> "step output: #{input}" end
          }
        ],
        condition: fn _output, _memory ->
          raise "Deliberate condition error"
        end
      }

      {:ok, agent} = Adk.create_agent(:loop, agent_config)
      {:error, reason} = Adk.run(agent, "initial input")

      assert match?({:condition_error, _, _}, reason)
    end
  end

  describe "config validation" do
    test "rejects missing required keys" do
      invalid_config = %{
        name: :missing_keys_test
        # Missing steps and condition
      }

      assert {:error, {:invalid_config, :missing_keys, keys}} =
               Adk.create_agent(:loop, invalid_config)

      assert :steps in keys
      assert :condition in keys
    end

    test "rejects invalid steps format" do
      invalid_config = %{
        name: :invalid_steps_test,
        steps: "not a list",
        condition: fn _, _ -> true end
      }

      assert {:error, {:invalid_config, :steps_not_a_list, "not a list"}} =
               Adk.create_agent(:loop, invalid_config)
    end

    test "rejects invalid condition function" do
      invalid_config = %{
        name: :invalid_condition_test,
        steps: [%{type: "function", function: fn x -> x end}],
        condition: "not a function"
      }

      assert {:error, {:invalid_config, :condition_not_function_arity_2, "not a function"}} =
               Adk.create_agent(:loop, invalid_config)
    end

    test "rejects invalid max_iterations" do
      invalid_config = %{
        name: :invalid_max_iterations_test,
        steps: [%{type: "function", function: fn x -> x end}],
        condition: fn _, _ -> true end,
        max_iterations: -1
      }

      assert {:error, {:invalid_config, :max_iterations_invalid, -1}} =
               Adk.create_agent(:loop, invalid_config)
    end
  end

  describe "server functionality" do
    test "get_state returns the current state" do
      agent_config = %{
        name: :get_state_test,
        steps: [%{type: "function", function: fn x -> x end}],
        condition: fn _, _ -> true end
      }

      {:ok, agent} = Adk.create_agent(:loop, agent_config)

      # Call get_state directly on the GenServer
      state = :sys.get_state(agent)

      # Verify state has expected structure
      assert state.config.name == :get_state_test
      assert is_binary(state.session_id)
    end
  end
end
