defmodule Adk.Test.AgentCase do
  @moduledoc """
  ExUnit case template for testing Adk agents.

  Provides helper functions and automatic setup for clean testing environments.
  """
  use ExUnit.CaseTemplate

  # Tell the compiler that these functions are used even though it can't detect it

  using do
    quote do
      import Adk.Test.Helpers
      alias Adk.Memory.InMemory
      import Mox
    end
  end
end
