defmodule Adk.ToolRegistryTest do
  use ExUnit.Case

  defmodule DummyTool do
    use Adk.Tool

    @impl true
    def definition do
      %{
        name: "dummy_tool",
        description: "A dummy tool for testing",
        parameters: %{}
      }
    end

    @impl true
    def execute(_params), do: {:ok, :dummy_result}
  end

  setup do
    # Only register the dummy tool; registries and supervisors are started by the application
    :ok
  end

  test "registers and looks up a tool" do
    assert :ok = Adk.ToolRegistry.register(DummyTool)
    assert {:ok, DummyTool} = Adk.ToolRegistry.lookup(:dummy_tool)
  end

  test "lists all registered tools" do
    Adk.ToolRegistry.register(DummyTool)
    assert DummyTool in Adk.ToolRegistry.list()
  end

  test "unregisters a tool" do
    Adk.ToolRegistry.register(DummyTool)
    assert :ok = Adk.ToolRegistry.unregister(:dummy_tool)
    assert {:error, :tool_not_found} = Adk.ToolRegistry.lookup(:dummy_tool)
  end

  test "returns error for invalid tool module" do
    defmodule InvalidTool do
    end

    assert {:error, :invalid_tool_module} = Adk.ToolRegistry.register(InvalidTool)
  end
end
