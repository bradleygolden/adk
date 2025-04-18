defmodule Adk.CallbackTest do
  use ExUnit.Case, async: false

  alias Adk.Callback
  require Logger

  setup do
    # Re-initialize the callback registry for each test
    Callback.init()

    # Unregister any existing callbacks to ensure clean test environment
    :ets.delete_all_objects(Callback.callback_registry_name())

    :ok
  end

  test "register and execute a single callback" do
    # Register a callback that adds 1 to the input
    Callback.register(:before_run, fn value, _context ->
      {:cont, value + 1}
    end)

    # Execute the callback
    {:ok, result} = Callback.execute(:before_run, 5, %{})

    assert result == 6
  end

  test "execute multiple callbacks in sequence" do
    # Register callbacks that transform the input
    Callback.register(:before_run, fn value, _context ->
      {:cont, value + 1}
    end)

    Callback.register(:before_run, fn value, _context ->
      {:cont, value * 2}
    end)

    # Execute the callbacks
    {:ok, result} = Callback.execute(:before_run, 5, %{})

    # First callback: 5 + 1 = 6
    # Second callback: 6 * 2 = 12
    assert result == 12
  end

  test "halt the callback chain" do
    # Register a callback that continues
    Callback.register(:before_run, fn value, _context ->
      {:cont, value + 1}
    end)

    # Register a callback that halts
    Callback.register(:before_run, fn value, _context ->
      {:halt, value * 10}
    end)

    # Register a callback that should not be executed
    Callback.register(:before_run, fn value, _context ->
      {:cont, value + 100}
    end)

    # Execute the callbacks
    {:halt, result} = Callback.execute(:before_run, 5, %{})

    # First callback: 5 + 1 = 6
    # Second callback: 6 * 10 = 60 (halts here)
    # Third callback: should not execute
    assert result == 60
  end

  test "filter callbacks by context" do
    # Register a callback for agent1
    Callback.register(
      :before_run,
      fn value, _context ->
        {:cont, value + 1}
      end,
      %{agent_name: "agent1"}
    )

    # Register a callback for agent2
    Callback.register(
      :before_run,
      fn value, _context ->
        {:cont, value * 2}
      end,
      %{agent_name: "agent2"}
    )

    # Execute for agent1
    {:ok, result1} = Callback.execute(:before_run, 5, %{agent_name: "agent1"})

    # Execute for agent2
    {:ok, result2} = Callback.execute(:before_run, 5, %{agent_name: "agent2"})

    # Execute with no matching filter
    {:ok, result3} = Callback.execute(:before_run, 5, %{agent_name: "agent3"})

    # Only agent1's callback ran: 5 + 1
    assert result1 == 6
    # Only agent2's callback ran: 5 * 2
    assert result2 == 10
    # No matching callbacks
    assert result3 == 5
  end

  test "unregister callback by ID" do
    # Register a callback and get its ID
    Callback.register(:before_run, fn value, _context ->
      {:cont, value + 1}
    end)

    # Get the ID of the registered callback
    [{:before_run, [{id, _, _}]}] = :ets.lookup(Callback.callback_registry_name(), :before_run)

    # Unregister the callback
    :ok = Callback.unregister(:before_run, id)

    # Execute and verify it's gone
    {:ok, result} = Callback.execute(:before_run, 5, %{})
    # Value unchanged
    assert result == 5
  end

  test "unregister callbacks by filter" do
    # Register callbacks for different agents
    Callback.register(
      :before_run,
      fn value, _context ->
        {:cont, value + 1}
      end,
      %{agent_name: "agent1"}
    )

    Callback.register(
      :before_run,
      fn value, _context ->
        {:cont, value * 2}
      end,
      %{agent_name: "agent1"}
    )

    Callback.register(
      :before_run,
      fn value, _context ->
        {:cont, value - 1}
      end,
      %{agent_name: "agent2"}
    )

    # Unregister all callbacks for agent1
    {:ok, count} = Callback.unregister_by_filter(:before_run, %{agent_name: "agent1"})
    assert count == 2

    # Verify only agent2's callback remains
    {:ok, result} = Callback.execute(:before_run, 5, %{agent_name: "agent1"})
    # Unchanged for agent1
    assert result == 5

    {:ok, result} = Callback.execute(:before_run, 5, %{agent_name: "agent2"})
    # 5 - 1 for agent2
    assert result == 4
  end

  test "handle callback errors" do
    # Register a callback that raises an error
    Callback.register(:before_run, fn _value, _context ->
      raise "Deliberate error in callback"
    end)

    # Register a second callback that should still execute
    Callback.register(:before_run, fn value, _context ->
      {:cont, value * 2}
    end)

    # Verify execution continues after error
    {:ok, result} = Callback.execute(:before_run, 5, %{})

    # First callback raises but is rescued, second callback executes
    assert result == 10
  end
end
