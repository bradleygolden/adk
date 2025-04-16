defmodule Adk.MemoryTest do
  use ExUnit.Case

  setup do
    # The memory service is already started by the application
    # Clear any existing data between tests
    Adk.clear_memory(:in_memory, "test-session-#{:erlang.unique_integer([:positive])}")
    :ok
  end

  test "stores and retrieves state data" do
    session_id = "test-session-state-#{:rand.uniform(1000)}"
    test_key = :my_data
    test_value = %{info: "Test data to remember", count: 5}

    # Update state
    :ok = Adk.Memory.update_state(:in_memory, session_id, test_key, test_value)

    # Retrieve specific state
    {:ok, retrieved_value} = Adk.Memory.get_state(:in_memory, session_id, test_key)
    assert retrieved_value == test_value

    # Retrieve full state
    {:ok, full_state} = Adk.Memory.get_full_state(:in_memory, session_id)
    assert full_state == %{my_data: test_value}
  end

  test "adds and retrieves message history" do
    session_id = "test-session-history-#{:rand.uniform(1000)}"
    # Event opts require :author
    event_opts1 = %{author: :user, content: "Hello"}
    event_opts2 = %{author: :assistant, content: "Hi there!"}

    # Add messages
    :ok = Adk.Memory.add_message(:in_memory, session_id, event_opts1)
    :ok = Adk.Memory.add_message(:in_memory, session_id, event_opts2)

    # Retrieve history
    {:ok, history} = Adk.Memory.get_history(:in_memory, session_id)

    # Verify history (should be in chronological order)
    assert length(history) == 2
    # Check event fields
    assert Enum.at(history, 0).author == :user
    assert Enum.at(history, 0).content == "Hello"
    assert Enum.at(history, 1).author == :assistant
    assert Enum.at(history, 1).content == "Hi there!"
  end

  test "searches message history" do
    session_id = "test-session-search-#{:rand.uniform(1000)}"

    # Add multiple messages
    :ok =
      Adk.Memory.add_message(:in_memory, session_id, %{
        author: :user,
        content: "Info about apples"
      })

    :ok =
      Adk.Memory.add_message(:in_memory, session_id, %{
        author: :user,
        content: "Info about bananas"
      })

    :ok =
      Adk.Memory.add_message(:in_memory, session_id, %{
        author: :user,
        content: "Info about oranges"
      })

    # Search for specific term in history content
    {:ok, results} = Adk.Memory.search(:in_memory, session_id, "bananas")

    # Verify search works
    assert length(results) == 1
    assert results |> hd() |> Map.get(:content) |> String.contains?("bananas")

    # Search for common term
    {:ok, results} = Adk.Memory.search(:in_memory, session_id, "Info about")
    assert length(results) == 3
  end

  test "clears memory for a session" do
    session_id = "test-session-clear-#{:rand.uniform(1000)}"

    # Add state and history
    :ok = Adk.Memory.update_state(:in_memory, session_id, :data, "Test data")

    :ok =
      Adk.Memory.add_message(:in_memory, session_id, %{author: :user, content: "Test message"})

    # Verify state is there
    {:ok, value} = Adk.Memory.get_state(:in_memory, session_id, :data)
    assert value == "Test data"
    # Verify history is there
    {:ok, history} = Adk.Memory.get_history(:in_memory, session_id)
    assert length(history) == 1

    # Clear the memory for the session
    # clear_sessions clears the whole entry
    :ok = Adk.Memory.clear_sessions(:in_memory, session_id)

    # Verify state is gone (returns session_not_found error)
    assert {:error, {:session_not_found, ^session_id}} =
             Adk.Memory.get_state(:in_memory, session_id, :data)

    # Verify history is gone (returns session_not_found error)
    assert {:error, {:session_not_found, ^session_id}} =
             Adk.Memory.get_history(:in_memory, session_id)
  end

  test "memory tool can save and get state" do
    Adk.register_tool(Adk.Tools.MemoryTool)
    session_id = "tool-test-state-#{:rand.uniform(1000)}"
    test_key = "my_tool_data"
    test_value = "Information stored via tool state"

    # Use memory tool to save state
    context = %{session_id: session_id, invocation_id: nil, tool_call_id: nil}

    {:ok, save_result} =
      Adk.ToolRegistry.execute_tool(
        :memory_tool,
        %{
          "action" => "save_state",
          "session_id" => session_id,
          "key" => test_key,
          "data" => test_value
        },
        context
      )

    assert String.contains?(save_result, "State saved for key '#{test_key}'")

    # Use memory tool to retrieve state
    {:ok, get_result} =
      Adk.ToolRegistry.execute_tool(
        :memory_tool,
        %{
          "action" => "get_state",
          "session_id" => session_id,
          "key" => test_key
        },
        context
      )

    assert String.contains?(get_result, test_value)
  end

  test "memory tool can add and get history" do
    Adk.register_tool(Adk.Tools.MemoryTool)
    session_id = "tool-test-history-#{:rand.uniform(1000)}"

    # Note: The MemoryTool now expects the 'data' for add_message to contain event options, like :author
    test_event_opts = %{"author" => "user", "content" => "Message added via tool"}
    context = %{session_id: session_id, invocation_id: nil, tool_call_id: nil}

    # Use memory tool to add message
    {:ok, add_result} =
      Adk.ToolRegistry.execute_tool(
        :memory_tool,
        %{
          "action" => "add_message",
          "session_id" => session_id,
          # Tool expects map data for add_message
          "data" => test_event_opts
        },
        context
      )

    assert String.contains?(add_result, "Message event added to history")

    # Use memory tool to retrieve history
    {:ok, get_result} =
      Adk.ToolRegistry.execute_tool(
        :memory_tool,
        %{
          "action" => "get_history",
          "session_id" => session_id
        },
        context
      )

    # Check if the retrieved history contains the message content
    assert String.contains?(get_result, "Message added via tool")
    # Check the event count and formatting
    assert String.contains?(get_result, "Retrieved 1 history events")
    # Check for string representation "user", not atom ":user"
    assert String.contains?(get_result, "Author: user")
  end
end
