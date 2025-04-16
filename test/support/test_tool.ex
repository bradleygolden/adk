defmodule Adk.AgentsTest.TestTool do
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

  @impl Adk.Tool
  def execute(%{"input" => input}, _context) do
    {:ok, "Processed: #{input}"}
  end
end
