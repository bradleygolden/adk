defmodule Adk.ToolRegistry do
  @moduledoc """
  Registry for managing available tools in the ADK framework.
  """

  # Note: This module assumes Adk.ToolRegistry.Registry is started elsewhere (e.g., Application Supervisor)
  # It acts as a direct API wrapper around Registry functions.

  @registry_name Adk.ToolRegistry.Registry

  @doc """
  Register a new tool module.

  The module must implement the `Adk.Tool` behaviour.
  """
  def register(tool_module) do
    if implements_tool_behavior?(tool_module) do
      try do
        definition = tool_module.definition()
        tool_name = definition.name |> String.to_atom()

        case Registry.register(@registry_name, tool_name, tool_module) do
          {:ok, _pid} ->
            :ok

          # Treat re-registration as success, maybe log a warning?
          {:error, {:already_registered, _pid}} ->
            # Logger.warning("Tool #{tool_name} already registered.")
            :ok
        end
      rescue
        e ->
          # Catch potential errors during definition() call or atom conversion
          {:error, {:registration_failed, :definition_error, tool_module, e}}
      end
    else
      {:error, {:invalid_tool_module, tool_module}}
    end
  end

  @doc """
  Unregister a tool module by its name (as an atom or string).
  """
  def unregister(tool_name) when is_binary(tool_name) do
    unregister(String.to_atom(tool_name))
  end

  def unregister(tool_name) when is_atom(tool_name) do
    Registry.unregister(@registry_name, tool_name)
    # Unregister doesn't return error if key doesn't exist
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
    case Registry.lookup(@registry_name, tool_name) do
      [{_pid, tool_module}] -> {:ok, tool_module}
      [] -> {:error, {:tool_not_found, tool_name}}
    end
  end

  @doc """
  List all registered tool modules.
  """
  def list do
    # Match spec to retrieve only the values (tool modules) from the registry
    match_spec = [{{:"$1", :"$2", :"$3"}, [], [:"$3"]}]
    Registry.select(@registry_name, match_spec)
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
  @spec execute_tool(tool_name :: atom() | String.t(), params :: map(), context :: map()) ::
          {:ok, any()} | {:error, term()}
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
