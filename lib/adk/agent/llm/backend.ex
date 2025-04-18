defmodule Adk.Agent.LLM.Backend do
  @moduledoc """
  Behaviour for LLM agent backends. All backends must implement the run/2 function.
  """
  @callback run(agent :: struct(), input :: any()) :: {:ok, any()} | {:error, any()}
end
