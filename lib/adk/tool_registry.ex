defmodule Adk.ToolRegistry do
  @moduledoc """
  Registry for managing available tools in the ADK framework.
  """
  use GenServer

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Register a new tool module.
  """
  def register(tool_module) do
    GenServer.call(__MODULE__, {:register, tool_module})
  end

  @doc """
  Unregister a tool module.
  """
  def unregister(tool_name) do
    GenServer.call(__MODULE__, {:unregister, tool_name})
  end

  @doc """
  Look up a tool module by name.
  """
  def lookup(tool_name) do
    GenServer.call(__MODULE__, {:lookup, tool_name})
  end

  @doc """
  List all registered tools.
  """
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # Server callbacks

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, tool_module}, _from, state) do
    # Ensure the module implements the Tool behavior
    if implements_tool_behavior?(tool_module) do
      # Get the tool definition to extract the name
      definition = tool_module.definition()
      tool_name = definition.name |> String.to_atom()
      
      # Register the tool
      Registry.register(Adk.ToolRegistry.Registry, tool_name, tool_module)
      
      new_state = Map.put(state, tool_name, tool_module)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :invalid_tool_module}, state}
    end
  end

  @impl true
  def handle_call({:unregister, tool_name}, _from, state) do
    # Remove from registry
    Registry.unregister(Adk.ToolRegistry.Registry, tool_name)
    
    # Remove from state
    new_state = Map.delete(state, tool_name)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:lookup, tool_name}, _from, state) do
    case Map.fetch(state, tool_name) do
      {:ok, tool_module} -> {:reply, {:ok, tool_module}, state}
      :error -> {:reply, {:error, :tool_not_found}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    tool_modules = Map.values(state)
    {:reply, tool_modules, state}
  end

  # Private functions

  defp implements_tool_behavior?(module) do
    functions = module.__info__(:functions)
    Keyword.has_key?(functions, :execute) && Keyword.has_key?(functions, :definition)
  end
end