defmodule Adk.Agent.SequentialTest do
  use ExUnit.Case, async: true

  alias Adk.Agent
  alias Adk.Agent.Sequential
  alias Adk.Agent.Server
  alias Adk.Memory

  setup do
    # Register test tool
    Adk.register_tool(Adk.AgentTest.TestTool)
    # Create a test session for memory
    session_id = "test-session-#{:rand.uniform(1000)}"
    Memory.clear_sessions(session_id)
    # Return the session_id to be used in tests
    {:ok, %{session_id: session_id}}

    :ok
  end

  describe "Sequential.run/2 (direct struct execution)" do
    test "executes steps in order" do
      config = %{
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

      {:ok, agent_struct} = Sequential.new(config)
      {:ok, result} = Agent.run(agent_struct, "test input")

      # Assuming Agent.run now returns {:ok, %{output: ...}}
      assert result == %{output: "Step 2: Step 1: test input"}
    end

    test "returns error if a step fails" do
      failing_function = fn _input ->
        raise "Step failed intentionally"
      end

      config = %{
        name: :sequential_error_test,
        steps: [
          %{type: "function", function: failing_function},
          %{
            type: "function",
            function: fn input -> "Should not run: #{input}" end
          }
        ]
      }

      {:ok, agent_struct} = Sequential.new(config)
      result = Agent.run(agent_struct, "irrelevant input")

      assert {:error,
              {:step_execution_error, :function, _,
               %RuntimeError{message: "Step failed intentionally"}}} = result
    end

    test "handles empty input" do
      config = %{
        name: :sequential_empty_input_test,
        steps: [
          %{
            type: "function",
            function: fn input -> input end
          }
        ]
      }

      {:ok, agent_struct} = Sequential.new(config)
      {:ok, result} = Agent.run(agent_struct, "")
      assert result == %{output: ""}
    end

    test "returns error for invalid config" do
      # Missing :steps
      invalid_config = %{name: :bad_config}
      assert {:error, {:invalid_config, :missing_keys, [:steps]}} = Sequential.new(invalid_config)

      invalid_config_steps = %{name: :bad_config, steps: :not_a_list}

      assert {:error, {:invalid_config, :steps_not_a_list, :not_a_list}} =
               Sequential.new(invalid_config_steps)

      invalid_step_format = %{name: :bad_config, steps: ["not_a_map"]}

      assert {:error, {:invalid_config, :unexpected_error, _}} =
               Sequential.new(invalid_step_format)
    end
  end

  describe "Sequential via Agent.Server" do
    test "executes steps via server" do
      config = %{
        name: :sequential_server_test,
        steps: [
          %{type: "function", function: fn input -> "Server Step 1: #{input}" end},
          %{type: "function", function: fn input -> "Server Step 2: #{input}" end}
        ]
      }

      {:ok, agent_struct} = Sequential.new(config)
      {:ok, pid} = Server.start_link(agent_struct)
      {:ok, result} = Server.run(pid, "server input")

      assert result == %{output: "Server Step 2: Server Step 1: server input"}
    end

    test "returns error via server if step fails" do
      failing_function = fn _input ->
        raise "Server step failed"
      end

      config = %{
        name: :sequential_server_error,
        steps: [%{type: "function", function: failing_function}]
      }

      {:ok, agent_struct} = Sequential.new(config)
      {:ok, pid} = Server.start_link(agent_struct)
      result = Server.run(pid, "server error input")

      # Server.run wraps the error in different format
      # Allow either error format
      case result do
        {:error, {:agent_execution_error, %RuntimeError{message: "Server step failed"}}} ->
          assert true

        {:error,
         {:step_execution_error, :function, _, %RuntimeError{message: "Server step failed"}}} ->
          assert true

        other ->
          flunk("Expected error for failed step, got: #{inspect(other)}")
      end
    end

    test "server call times out if agent is slow" do
      config = %{
        name: :sequential_server_timeout,
        steps: [
          %{
            type: "function",
            function: fn _input ->
              # Wait longer than the timeout
              :timer.sleep(100)
              "done"
            end
          }
        ]
      }

      {:ok, agent_struct} = Sequential.new(config)
      {:ok, pid} = Server.start_link(agent_struct)

      # Expect the GenServer.call to exit with timeout
      assert catch_exit(Server.run(pid, "input", 50)) ==
               {:timeout, {GenServer, :call, [pid, {:run, "input"}, 50]}}
    end

    test "server returns error if agent struct does not implement behaviour" do
      bad_struct = %{name: :not_an_agent}
      assert {:error, {:invalid_agent, _}} = Server.start_link(bad_struct)
    end
  end

  describe "Sequential.execute_step/5" do
    test "executes tool step type", context do
      session_id = context[:session_id]
      # Configure agent with tool step
      config = %{
        name: :sequential_tool_test,
        session_id: session_id,
        steps: [
          %{
            type: "tool",
            tool: "test_tool",
            params: %{"test_input" => "tool_test"}
          }
        ]
      }

      {:ok, agent_struct} = Sequential.new(config)
      {:ok, result} = Agent.run(agent_struct, "irrelevant for tool step")

      assert result == %{output: "Processed tool_test"}
    end

    test "handles error in tool execution" do
      # Configure agent with invalid tool parameters
      config = %{
        name: :sequential_tool_error_test,
        steps: [
          %{
            type: "tool",
            tool: "test_tool",
            params: %{"invalid_param" => "should_fail"}
          }
        ]
      }

      {:ok, agent_struct} = Sequential.new(config)
      result = Agent.run(agent_struct, "irrelevant for tool step")

      assert {:error, {:step_execution_error, :tool, "test_tool", _}} = result
    end

    test "executes transform step type with memory integration", context do
      session_id = context[:session_id]
      # First add some data to memory
      :ok =
        Memory.add_message(:in_memory, session_id,
          content: "memory data",
          author: :user,
          session_id: session_id
        )

      # Get the memory state to verify it has the data we expect
      {:ok, memory_state} = Memory.get_full_state(:in_memory, session_id)
      assert is_map(memory_state)

      # Configure a simple transform function that just returns the input
      # We're not testing transform logic here, just that it executes without error
      transform_fn = fn input, _memory_state ->
        "#{input} transformed"
      end

      config = %{
        name: :sequential_transform_test,
        session_id: session_id,
        steps: [
          %{
            type: "transform",
            transform: transform_fn
          }
        ]
      }

      {:ok, agent_struct} = Sequential.new(config)
      {:ok, result} = Agent.run(agent_struct, "transform input")

      # Just verify that we got output that includes our transformed text
      assert is_map(result)
      assert %{output: output} = result
      assert output == "transform input transformed"
    end

    test "handles error in transform step", context do
      session_id = context[:session_id]
      # Configure agent with failing transform
      failing_transform = fn _input, _memory ->
        raise "Transform failed intentionally"
      end

      config = %{
        name: :sequential_transform_error_test,
        session_id: session_id,
        steps: [
          %{
            type: "transform",
            transform: failing_transform
          }
        ]
      }

      {:ok, agent_struct} = Sequential.new(config)
      result = Agent.run(agent_struct, "transform input")

      assert {:error,
              {:step_execution_error, :transform, _,
               %RuntimeError{message: "Transform failed intentionally"}}} = result
    end

    test "handles unknown step type" do
      # Configure agent with unknown step type
      config = %{
        name: :sequential_unknown_step_test,
        steps: [
          %{
            type: "unknown_type",
            some_param: "value"
          }
        ]
      }

      {:ok, agent_struct} = Sequential.new(config)
      result = Agent.run(agent_struct, "test input")

      assert {:error, {:step_execution_error, :unknown_type, _}} = result
    end
  end
end
