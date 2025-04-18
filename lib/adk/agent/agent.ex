defmodule Adk.Agent do
  @moduledoc """
  Defines the behaviour for ADK agents and provides a top-level execution function.

  Agents are defined as structs that implement the `run/2` callback defined
  by this behaviour. This promotes a functional approach where the core agent logic
  operates on its configuration struct and input data.

  For agents that require stateful execution or process-based management,
  use the `Adk.Agent.Server` module, which can wrap any struct implementing
  this behaviour within a GenServer.
  """

  @doc """
  The primary callback for executing an agent's logic.

  Implementations should take the agent's configuration struct and input data,
  perform the agent's task, and return the result.

  Expected return values:
  - `{:ok, result_map}`: Where `result_map` is typically a map containing at least an `:output` key.
  - `{:error, reason}`: Where `reason` describes the failure.
  """
  @callback run(agent :: struct(), input :: any()) :: {:ok, map()} | {:error, any()}

  @doc """
  Executes an agent struct with the given input.

  This function validates that the provided struct implements the `Adk.Agent`
  behaviour and then delegates the call to the specific agent module's `run/2`
  implementation.

  This allows for direct, stateless execution of an agent's logic.
  For stateful execution, use `Adk.Agent.Server`.
  """
  def run(%module{} = agent_struct, input) when is_atom(module) do
    # Attempt to derive the agent module from the config struct's module name
    # Example: Adk.Agent.Sequential.Config -> Adk.Agent.Sequential
    agent_module_name =
      module
      |> Module.split()
      |> Enum.drop(-1)
      |> Module.concat()

    # Check if the derived agent module exists and implements run/2
    if Code.ensure_loaded?(agent_module_name) and
         function_exported?(agent_module_name, :run, 2) do
      agent_module_name.run(agent_struct, input)
    else
      # Fallback or error if the convention doesn't match or module/function is missing
      # This preserves the original check as a fallback if the naming convention isn't met
      if Code.ensure_loaded?(module) and function_exported?(module, :run, 2) do
        module.run(agent_struct, input)
      else
        {
          :error,
          {:behaviour_not_implemented,
           "Could not find a valid run/2 implementation. Checked #{inspect(agent_module_name)} (derived) and #{inspect(module)} (struct's module). Ensure the agent module (e.g., Adk.Agent.Sequential) implements run/2."}
        }
      end
    end
  end
end
