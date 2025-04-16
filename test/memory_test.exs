defmodule Adk.MemoryTest do
  use ExUnit.Case

  setup do
    # The memory service is already started by the application
    # Clear any existing data between tests
    Adk.clear_memory(:in_memory, "test-session-#{:erlang.unique_integer([:positive])}")
    :ok
  end

  test "stores and retrieves data from memory" do
    session_id = "test-session-#{:rand.uniform(1000)}"
    test_data = "Test data to remember"
    
    # Add data to memory
    :ok = Adk.add_to_memory(:in_memory, session_id, test_data)
    
    # Retrieve all sessions
    {:ok, sessions} = Adk.get_memory(:in_memory, session_id)
    
    # Verify the data was stored
    assert length(sessions) == 1
    assert Enum.at(sessions, 0) == test_data
  end

  test "searches for data in memory" do
    session_id = "test-session-#{:rand.uniform(1000)}"
    
    # Add multiple data entries
    :ok = Adk.add_to_memory(:in_memory, session_id, "Data with apple information")
    :ok = Adk.add_to_memory(:in_memory, session_id, "Data with banana information")
    :ok = Adk.add_to_memory(:in_memory, session_id, "Data with orange information")
    
    # Search for specific term
    {:ok, results} = Adk.search_memory(:in_memory, session_id, "banana")
    
    # Verify search works
    assert length(results) == 1
    assert String.contains?(hd(results), "banana")
    
    # Search for common term
    {:ok, results} = Adk.search_memory(:in_memory, session_id, "information")
    assert length(results) == 3
  end

  test "clears memory" do
    session_id = "test-session-#{:rand.uniform(1000)}"
    
    # Add data
    :ok = Adk.add_to_memory(:in_memory, session_id, "Test data")
    
    # Verify it's there
    {:ok, sessions} = Adk.get_memory(:in_memory, session_id)
    assert length(sessions) == 1
    
    # Clear the memory
    :ok = Adk.clear_memory(:in_memory, session_id)
    
    # Verify it's gone
    {:ok, sessions} = Adk.get_memory(:in_memory, session_id)
    assert sessions == []
  end

  test "memory tool can be used" do
    # Register the memory tool
    Adk.register_tool(Adk.Tools.MemoryTool)
    
    session_id = "tool-test-#{:rand.uniform(1000)}"
    
    # Use memory tool to save data
    {:ok, save_result} = Adk.execute_tool(:memory_tool, %{
      "action" => "save",
      "session_id" => session_id,
      "data" => "Information stored via tool"
    })
    
    assert String.contains?(save_result, "Data saved to memory")
    
    # Use memory tool to retrieve data
    {:ok, get_result} = Adk.execute_tool(:memory_tool, %{
      "action" => "get",
      "session_id" => session_id
    })
    
    assert String.contains?(get_result, "Information stored via tool")
  end
end