defmodule Adk.Tool do
  @moduledoc """
  Behavior and utilities for implementing tools in the ADK framework.
  """

  @doc """
  Execute the tool with the provided parameters.
  """
  @callback execute(params :: map()) :: {:ok, any()} | {:error, term()}

  @doc """
  Get the tool's definition (name, description, parameters).
  """
  @callback definition() :: %{
    name: String.t(),
    description: String.t(),
    parameters: map()
  }

  @doc """
  Execute a tool by name with the given parameters.
  """
  def execute(tool_name, params) when is_atom(tool_name) do
    case Adk.ToolRegistry.lookup(tool_name) do
      {:ok, tool_module} -> tool_module.execute(params)
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(tool_module, params) when is_atom(tool_module) do
    tool_module.execute(params)
  end

  @doc """
  Macro to implement common tool functionality.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Adk.Tool

      # Default implementations
      @impl Adk.Tool
      def definition do
        %{
          name: module_name_to_string(__MODULE__),
          description: "No description provided",
          parameters: %{}
        }
      end

      # Helper to convert module name to string
      defp module_name_to_string(module) do
        module
        |> to_string()
        |> String.replace(~r/^Elixir\./, "")
        |> String.split(".")
        |> List.last()
        |> Macro.underscore()
      end

      # Allow overriding default implementations
      defoverridable [definition: 0]
    end
  end
end