defmodule Adk.AgentTest.TestTool do
  @behaviour Adk.Tool

  @impl true
  def definition do
    %{
      name: "test_tool",
      description: "A tool for testing agent functionality",
      parameters: %{
        type: "object",
        properties: %{
          test_input: %{
            type: "string",
            description: "Input for the test tool"
          }
        },
        required: ["test_input"]
      }
    }
  end

  @impl true
  def execute(%{"test_input" => input}, _context) do
    {:ok, "Processed #{input}"}
  end

  def execute(params, _context) do
    {:error, "Invalid parameters: #{inspect(params)}"}
  end
end
