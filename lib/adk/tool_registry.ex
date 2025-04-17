defmodule Adk.ToolRegistry do
  @moduledoc """
  Registry for managing available tools in the Adk framework.
  """

  # Note: This module assumes Adk.ToolRegistry.Registry is started elsewhere (e.g., Application Supervisor)
  # It acts as a direct API wrapper around Registry functions.

  @table :adk_tool_registry

  # Ensure ETS table for tool registry exists; safe to call concurrently
  defp ensure_table do
    try do
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])
    rescue
      ArgumentError -> :ok
    end
  end

  @doc """
  Register a new tool module.

  The module must implement the `Adk.Tool` behaviour.
  """
  def register(tool_name, tool_module) do
    ensure_table()

    with true <- implements_tool_behavior?(tool_module) do
      case :ets.insert_new(@table, {tool_name, tool_module}) do
        true -> :ok
        false -> {:error, :already_registered}
      end
    else
      false -> {:error, :not_a_tool_module}
    end
  end

  @doc """
  Unregister a tool module by its name (as an atom or string).
  """
  def unregister(tool_name) when is_binary(tool_name) do
    unregister(String.to_atom(tool_name))
  end

  def unregister(tool_name) when is_atom(tool_name) do
    :ets.delete(@table, tool_name)
    :ok
  end

  @doc """
  Look up a tool module by its name (as an atom or string).

  Returns `{:ok, module}` or `{:error, :tool_not_found}`.
  """
  def lookup(tool_name) when is_binary(tool_name) do
    lookup(String.to_atom(tool_name))
  end

  def lookup(tool_name) when is_atom(tool_name) do
    case :ets.lookup(@table, tool_name) do
      [{^tool_name, tool_module}] ->
        {:ok, tool_module}

      [] ->
        {:error, {:tool_not_found, tool_name}}
    end
  end

  @doc """
  List all registered tool modules.
  """
  def list do
    :ets.tab2list(@table)
    |> Enum.map(fn {_key, mod} -> mod end)
  end

  @doc """
  Execute a registered tool by name with the given parameters and context.

  Looks up the tool module and calls its `execute/2` function.

  ## Parameters
    * `tool_name` - The atom or string name of the tool to execute.
    * `params` - The map of parameters to pass to the tool's `execute/2` function.
    * `context` - The context map (containing `:session_id`, etc.) to pass to the tool's `execute/2` function. See `Adk.Tool.context/0`.

  ## Return Values
    * `{:ok, result}` - If the tool executes successfully.
    * `{:error, reason}` - If the tool is not found, execution fails, or returns an error.
      The `reason` will be a descriptive tuple, e.g., `{:tool_not_found, tool_name}` or
      `{:tool_execution_failed, tool_name, execution_reason}`.
  """
  def execute_tool(tool_name, params, context) when is_binary(tool_name) do
    execute_tool(String.to_atom(tool_name), params, context)
  end

  def execute_tool(tool_name, params, context)
      when is_atom(tool_name) and is_map(params) and is_map(context) do
    case lookup(tool_name) do
      {:ok, tool_module} ->
        try do
          # Call the tool's execute/2 function
          tool_module.execute(params, context)
        rescue
          # Catch runtime errors during tool execution
          e -> {:error, {:tool_execution_failed, tool_name, e, __STACKTRACE__}}
        catch
          # Catch throws during tool execution
          kind, value -> {:error, {:tool_execution_failed, tool_name, {kind, value}}}
        end

      {:error, _reason} = error ->
        # Tool not found
        error
    end
  end

  # Private functions

  defp implements_tool_behavior?(module) do
    # Check for execute/2 specifically
    functions = module.__info__(:functions)

    Keyword.has_key?(functions, :definition) &&
      Enum.any?(functions, fn {name, arity} -> name == :execute && arity == 2 end)
  end
end
