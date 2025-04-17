defmodule Adk.ToolTest do
  use ExUnit.Case, async: true

  # Define a dummy tool module using the Adk.Tool macro
  defmodule DummyTool do
    use Adk.Tool

    @impl Adk.Tool
    def execute(params, context), do: {:ok, {params, context}}
  end

  describe "default definition/0" do
    test "returns expected map with name, description, and empty parameters" do
      assert DummyTool.definition() == %{
               name: "dummy_tool",
               description: "No description provided",
               parameters: %{}
             }
    end
  end

  describe "execute/2 callback" do
    test "invokes the user-defined implementation" do
      params = %{"foo" => "bar"}
      context = %{session_id: "session1", invocation_id: "invoc1", tool_call_id: "call1"}

      assert DummyTool.execute(params, context) == {:ok, {params, context}}
    end
  end

  describe "default execute stub" do
    defmodule StubTool do
      use Adk.Tool
    end

    test "returns error tuple when execute/2 is not overridden" do
      result = StubTool.execute(%{}, %{})
      assert {:error, {:not_implemented, :execute, StubTool}} = result
    end
  end
end
