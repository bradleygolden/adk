defmodule Adk.ToolRegistry.Server do
  @moduledoc false
  use GenServer

  @table :adk_tool_registry

  @doc """
  Starts the ToolRegistry server, which owns the ETS table for tools.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Create the ETS table from a long-lived process to avoid table destruction
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    {:ok, %{}}
  end
end
