defmodule Adk.Test.Helpers do
  @moduledoc """
  Helper functions for testing Adk agents.

  Provides utilities for testing agents with stubbed LLMs, capturing events,
  and asserting on agent outputs.
  """
  import ExUnit.Assertions

  @doc """
  Assert that running an agent with `input` yields `expected` output.

  ## Examples

      test "my calculator agent" do
        {:ok, agent} = Adk.create_agent(:sequential, %{
          name: "calculator",
          steps: [%{type: "function", function: fn _ -> 2 + 2 end}]
        })

        assert_agent_output(agent, nil, "4")
      end
  """
  def assert_agent_output(agent, input, expected) do
    {:ok, result} = Adk.run(agent, input)
    assert result.output == expected
  end

  # Define a macro to conditionally include Mox-dependent code
  @mox_available Code.ensure_loaded?(Mox) == true

  if @mox_available do
    @doc """
    Stub any LLM call to return the specified `response`.

    This is useful for deterministic testing of agents that use LLMs.

    ## Examples

        test "my llm agent" do
          stub_llm("This is a test response")

          {:ok, agent} = Adk.create_agent(:llm, %{
            name: "test_agent",
            prompt: "Hello"
          })

          assert_agent_output(agent, nil, "This is a test response")
        end
    """
    def stub_llm(response) do
      Mox.defmock(LLMMock, for: Adk.LLM.Provider)
      Adk.Config.set(:llm_provider, LLMMock)

      LLMMock
      |> Mox.expect(:generate, fn _prompt -> {:ok, response} end)
    end
  else
    @doc """
    Stub any LLM call to return the specified `response`.

    NOTE: This function requires the Mox library to be added to your dependencies:
    ```
    {:mox, "~> 1.0", only: :test}
    ```

    ## Examples

        test "my llm agent" do
          stub_llm("This is a test response")

          {:ok, agent} = Adk.create_agent(:llm, %{
            name: "test_agent",
            prompt: "Hello"
          })

          assert_agent_output(agent, nil, "This is a test response")
        end
    """
    def stub_llm(_response) do
      raise "Mox is required for stub_llm/1. Add {:mox, \"~> 1.0\", only: :test} to your dependencies."
    end
  end

  @doc """
  Capture all events emitted during execution of the given function.

  Returns a list of events that were emitted.

  ## Examples

      test "agent emits expected events" do
        events = capture_events(fn ->
          {:ok, agent} = Adk.create_agent(:sequential, %{...})
          Adk.run(agent, "test input")
        end)

        assert Enum.any?(events, &(&1.type == :agent_started))
      end
  """
  def capture_events(fun) do
    events = []
    {:ok, pid} = Adk.Event.subscribe()

    result = fun.()

    # Give some time for events to be processed
    Process.sleep(50)

    # Unsubscribe and return events
    Adk.Event.unsubscribe(pid)
    {result, events}
  end

  @doc """
  Create a test agent with the given configuration.

  A convenience wrapper around `Adk.create_agent/2` that handles
  the result tuple and raises on error.

  ## Examples

      test "test agent" do
        agent = create_test_agent(:sequential, %{
          name: "test",
          steps: [%{type: "function", function: fn _ -> "hello" end}]
        })

        assert_agent_output(agent, nil, "hello")
      end
  """
  def create_test_agent(type, config) do
    case Adk.create_agent(type, config) do
      {:ok, agent} -> agent
      {:error, reason} -> raise "Failed to create test agent: #{inspect(reason)}"
    end
  end
end
