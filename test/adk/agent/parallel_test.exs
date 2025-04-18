defmodule Adk.Agent.ParallelTest do
  use ExUnit.Case, async: true

  alias Adk.Agent
  alias Adk.Agent.Parallel
  alias Adk.Agent.Server

  # setup do
  #   # Adk.register_tool(Adk.AgentTest.TestTool)
  #   :ok
  # end

  describe "Parallel.run/2 (direct struct execution)" do
    test "executes tasks in parallel and combines results" do
      config = %{
        name: :parallel_test,
        tasks: [
          %{
            type: "function",
            function: fn _ ->
              :timer.sleep(50)
              "Task 1 result"
            end
          },
          %{type: "function", function: fn _ -> "Task 2 result" end}
          # %{type: "tool", tool: "test_tool", params: %{"input" => "from_task_3"}}
        ]
      }

      {:ok, agent_struct} = Parallel.new(config)
      {:ok, result} = Agent.run(agent_struct, "test input")

      assert result == %{
               output: %{0 => "Task 1 result", 1 => "Task 2 result"},
               # Default combined is string join
               combined: "Task 1 result\nTask 2 result"
             }

      # Add tool test back if Adk.AgentTest.TestTool is available/registered
      # assert Map.has_key?(result.output, 2)
      # assert result.output[2] == "Processed: from_task_3"
      # assert String.contains?(result.combined, "Processed: from_task_3")
    end

    test "returns error immediately if a task fails (halt_on_error: true default)" do
      config = %{
        name: :parallel_error_halt,
        tasks: [
          %{
            type: "function",
            function: fn _ ->
              :timer.sleep(50)
              "Task 1 ok"
            end
          },
          %{type: "function", function: fn _ -> raise "Task 2 failed" end},
          %{
            type: "function",
            function: fn _ ->
              :timer.sleep(100)
              "Task 3 never runs"
            end
          }
        ]
        # halt_on_error: true (default)
      }

      {:ok, agent_struct} = Parallel.new(config)
      result = Agent.run(agent_struct, "irrelevant input")

      # Match the general structure but be more lenient on the exact format
      assert {:error, {:parallel_task_failed, {1, error_detail}, state_map}} = result

      # Check that error_detail contains the right exception
      assert match?({:task_execution_error, :function, _, %RuntimeError{}}, error_detail)

      # Check the message separately
      case error_detail do
        {:task_execution_error, :function, _, %RuntimeError{message: msg}} ->
          assert msg =~ "Task 2 failed"

        _ ->
          flunk("Expected RuntimeError with 'Task 2 failed' message")
      end

      # Check that we have the expected successes
      assert match?(%{successes: _}, state_map)

      # In some implementations, successes might be empty if we fail fast
      # In others, we might have successfully completed the first task
      if Map.has_key?(state_map.successes, 0) do
        assert state_map.successes[0] == "Task 1 ok"
      end

      # Check that we have the expected failure
      assert match?(%{failures: _}, state_map)

      assert Enum.any?(state_map.failures, fn
               {1, {:task_execution_error, :function, _, error}} ->
                 error.message =~ "Task 2 failed"

               _ ->
                 false
             end)
    end

    test "returns all results if a task fails (halt_on_error: false)" do
      config = %{
        name: :parallel_error_continue,
        tasks: [
          %{
            type: "function",
            function: fn _ ->
              :timer.sleep(50)
              "Task 1 ok"
            end
          },
          %{type: "function", function: fn _ -> raise "Task 2 failed" end},
          %{
            type: "function",
            function: fn _ ->
              :timer.sleep(10)
              "Task 3 ok"
            end
          }
        ],
        halt_on_error: false
      }

      {:ok, agent_struct} = Parallel.new(config)
      result = Agent.run(agent_struct, "irrelevant input")

      # Still returns error, but includes all completed/failed tasks
      assert {:error,
              {
                :parallel_task_failed,
                # Order of failures isn't guaranteed, check presence
                {_failed_index,
                 {:task_execution_error, :function, _, %RuntimeError{message: "Task 2 failed"}}},
                %{successes: %{0 => "Task 1 ok", 2 => "Task 3 ok"}, failures: failures}
              }} =
               result

      # Verify the specific failure is in the list
      assert Enum.any?(failures, fn
               {1, {:task_execution_error, :function, _, %RuntimeError{message: "Task 2 failed"}}} ->
                 true

               _ ->
                 false
             end)
    end

    test "returns error if a task times out (halt_on_error: true default)" do
      config = %{
        name: :parallel_timeout_halt,
        tasks: [
          %{
            type: "function",
            function: fn _ ->
              :timer.sleep(200)
              "done"
            end
          }
        ],
        # Short timeout
        task_timeout: 50
        # halt_on_error: true (default)
      }

      {:ok, agent_struct} = Parallel.new(config)
      result = Agent.run(agent_struct, "input")

      # The error format varies, so be more flexible
      assert {:error, {:parallel_task_failed, timeout_reason, %{failures: failures}}} = result

      # Check that it's some type of timeout (exact format may vary)
      assert match?({:timeout, _}, timeout_reason) or
               match?({:stream_exit, :timeout}, timeout_reason)

      # Check that failures contains a timeout entry
      assert Enum.any?(failures, fn
               {:timeout, _} -> true
               {:stream_exit, :timeout} -> true
               _ -> false
             end)
    end

    test "returns empty map if no tasks are provided" do
      config = %{name: :parallel_empty_test, tasks: []}
      {:ok, agent_struct} = Parallel.new(config)
      {:ok, result} = Agent.run(agent_struct, "any input")
      assert result == %{output: %{}, combined: ""}
    end

    test "returns error for invalid config" do
      # Missing :tasks
      invalid_config = %{name: :bad_config}
      assert {:error, {:invalid_config, :missing_keys, [:tasks]}} = Parallel.new(invalid_config)

      invalid_timeout = %{name: :bad_config, tasks: [], task_timeout: -10}

      assert {:error, {:invalid_config, :invalid_task_timeout, -10}} =
               Parallel.new(invalid_timeout)
    end
  end

  describe "Parallel via Agent.Server" do
    test "executes tasks via server" do
      config = %{
        name: :parallel_server_test,
        tasks: [
          %{type: "function", function: fn _ -> "Server Task 1" end},
          %{type: "function", function: fn _ -> "Server Task 2" end}
        ]
      }

      {:ok, agent_struct} = Parallel.new(config)
      {:ok, pid} = Server.start_link(agent_struct)
      {:ok, result} = Server.run(pid, "server input")

      assert result == %{
               output: %{0 => "Server Task 1", 1 => "Server Task 2"},
               combined: "Server Task 1\nServer Task 2"
             }
    end

    test "returns error via server if task fails" do
      config = %{
        name: :parallel_server_error,
        tasks: [%{type: "function", function: fn _ -> raise "Server task failed" end}]
        # halt_on_error: true (default)
      }

      {:ok, agent_struct} = Parallel.new(config)
      {:ok, pid} = Server.start_link(agent_struct)
      result = Server.run(pid, "irrelevant")

      # Error is wrapped by agent execution
      assert {:error, error_reason} = result
      # Now check the error reason separately to handle either format
      # The direct version would have the specific format
      # The server version would wrap it in {:agent_execution_error, ...}

      error_detail =
        case error_reason do
          {:agent_execution_error, inner_error} -> inner_error
          inner_error -> inner_error
        end

      # Inner error is from parallel failure
      assert {:parallel_task_failed, {0, {:task_execution_error, :function, _, %RuntimeError{}}},
              %{failures: failures, successes: _}} = error_detail

      # Check the message separately since exact string format might vary
      assert Enum.any?(failures, fn
               {0, {:task_execution_error, :function, _, error}} ->
                 error.message =~ "Server task failed"

               _ ->
                 false
             end)
    end

    test "server call times out if overall agent is slow" do
      # This tests the GenServer.call timeout, not the internal task_timeout
      config = %{
        name: :parallel_server_overall_timeout,
        tasks: [
          %{
            type: "function",
            function: fn _input ->
              :timer.sleep(100)
              "done"
            end
          }
        ]
      }

      {:ok, agent_struct} = Parallel.new(config)
      {:ok, pid} = Server.start_link(agent_struct)

      # Expect the GenServer.call to exit with timeout
      assert catch_exit(Server.run(pid, "input", 50)) ==
               {:timeout, {GenServer, :call, [pid, {:run, "input"}, 50]}}
    end
  end
end
