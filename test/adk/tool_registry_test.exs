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

    @impl Adk.Tool
    def execute(_params, _context), do: {:ok, :dummy_result}
  end

  setup do
    # Clear the registry before each test
    for tool <- Adk.ToolRegistry.list() do
      name =
        case tool.definition()[:name] do
          n when is_binary(n) -> String.to_atom(n)
          n when is_atom(n) -> n
          _ -> tool
        end

      Adk.ToolRegistry.unregister(name)
    end

    :ok
  end

  test "registers and looks up a tool" do
    assert :ok = Adk.ToolRegistry.register(:dummy_tool, DummyTool)
    assert {:ok, DummyTool} = Adk.ToolRegistry.lookup(:dummy_tool)
  end

  test "lists all registered tools" do
    Adk.ToolRegistry.register(:dummy_tool, DummyTool)
    assert DummyTool in Adk.ToolRegistry.list()
  end

  test "unregisters a tool" do
    Adk.ToolRegistry.register(:dummy_tool, DummyTool)
    assert :ok = Adk.ToolRegistry.unregister(:dummy_tool)
    assert {:error, {:tool_not_found, :dummy_tool}} = Adk.ToolRegistry.lookup(:dummy_tool)
  end

  test "returns error for invalid tool module" do
    defmodule InvalidTool do
    end

    assert {:error, :not_a_tool_module} = Adk.ToolRegistry.register(:invalid_tool, InvalidTool)
  end

  # Tests for concurrent registration and unregistration scenarios
  test "concurrent registration only allows one registration" do
    name = :concurrent_tool
    module = DummyTool

    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          Adk.ToolRegistry.register(name, module)
        end)
      end

    results =
      tasks
      |> Enum.map(&Task.await(&1, 5_000))

    assert Enum.count(results, fn x -> x == :ok end) == 1
    assert Enum.count(results, fn x -> x == {:error, :already_registered} end) == 4
    assert {:ok, _module} = Adk.ToolRegistry.lookup(name)
  end

  test "concurrent unregister always returns ok and removes tool once" do
    name = :dummy_tool
    module = DummyTool
    Adk.ToolRegistry.register(name, module)

    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          Adk.ToolRegistry.unregister(name)
        end)
      end

    results =
      tasks
      |> Enum.map(&Task.await(&1, 5_000))

    # Ensure all unregisters have completed before lookup
    assert Enum.count(results, &(&1 == :ok)) >= 1
    # Small delay to ensure ETS visibility
    :timer.sleep(50)
    assert {:error, {:tool_not_found, _name}} = Adk.ToolRegistry.lookup(name)
  end
end
