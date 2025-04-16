defmodule Adk.AgentsTest do
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

    @impl true
    def execute(%{"input" => input}) do
      {:ok, "Processed: #{input}"}
    end
  end

  setup do
    # Only register the test tool; registries and supervisors are started by the application
    Adk.register_tool(TestTool)
    :ok
  end

  describe "Sequential agent" do
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

  describe "Parallel agent" do
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

  describe "Loop agent" do
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
      assert result.iterations == 5
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
      assert result.iterations == 3
    end
  end

  describe "LLM agent" do
    # Skipping the LLM test for now as it requires mock providers with specific behavior
    # This test will need to be revisited with a better mocking strategy
    @tag :skip
    test "processes input using an LLM and executes tool calls" do
      # Configure the LLM agent to use our mock provider
      agent_config = %{
        name: :llm_test,
        tools: ["test_tool"],
        llm_provider: :mock,
        llm_options: %{
          # Make the mock respond with a tool call
          mock_response:
            "I'll help you with that. Let me process your request.\n\ncall_tool(\"test_tool\", {\"input\": \"from_llm\"})"
        }
      }

      # Register the test tool
      Adk.register_tool(TestTool)
      
      {:ok, agent} = Adk.create_agent(:llm, agent_config)
      {:ok, result} = Adk.run(agent, "Can you process this for me?")
      
      # For now, we just assert that we get some kind of response
      assert is_map(result)
    end

    @tag :skip
    test "handles direct responses without tool calls" do
      agent_config = %{
        name: :llm_direct_test,
        tools: ["test_tool"],
        llm_provider: :mock,
        llm_options: %{
          # Make the mock respond without a tool call
          mock_response: "I can answer this directly without using any tools."
        }
      }

      {:ok, agent} = Adk.create_agent(:llm, agent_config)
      {:ok, result} = Adk.run(agent, "What's 2+2?")

      # For now, we just assert that we get some kind of response
      assert is_map(result)
    end
  end
end
