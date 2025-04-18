defmodule Adk.Agent.Server do
  @moduledoc """
  A generic GenServer for running any agent struct that implements the `Adk.Agent` behaviour.

  This server manages the process lifecycle and state for an agent struct,
  allowing potentially stateful interactions over time via a consistent process-based API.
  It delegates the core execution logic to the `run/2` function of the specific
  agent struct it holds.
  """
  use GenServer
  require Logger
  require UUID

  @default_timeout 5000

  # --- Public API ---

  @doc """
  Starts the agent server linked to the current process.

  Args:
    - `agent_struct`: An agent configuration struct (e.g., `%Adk.Agent.Sequential{}`)
      that implements the `Adk.Agent` behaviour.
    - `opts`: A keyword list of options for `GenServer.start_link/3`.
      Common options include `:name` to register the process.

  Returns:
    - `{:ok, pid}` if the server starts successfully.
    - `{:error, reason}` otherwise.
  """
  def start_link(agent_struct, opts \\ []) do
    # Guard against non-structs
    unless is_map(agent_struct) && Map.has_key?(agent_struct, :__struct__) do
      {:error, {:invalid_agent, "Expected agent struct, got: #{inspect(agent_struct)}"}}
    else
      struct_module = agent_struct.__struct__

      # Attempt to derive the agent module from the config struct's module name
      agent_module_name =
        struct_module
        |> Module.split()
        |> Enum.drop(-1)
        |> Module.concat()

      # Check if the *derived agent module* implements the run/2 callback
      unless Code.ensure_loaded?(agent_module_name) and
               function_exported?(agent_module_name, :run, 2) do
        {:error,
         {:invalid_agent,
          "Agent module #{inspect(agent_module_name)} derived from #{inspect(struct_module)} does not implement run/2 required by Adk.Agent"}}
      else
        GenServer.start_link(__MODULE__, agent_struct, opts)
      end
    end
  end

  @doc """
  Runs the agent process with the given input.

  Sends a synchronous `:run` call to the agent server.

  Args:
    - `server`: The pid, registered name, or `{:via, module, name}` tuple of the agent server.
    - `input`: The input data to pass to the agent's `run/2` function.
    - `timeout`: The maximum time in milliseconds to wait for a reply (defaults to #{@default_timeout}).

  Returns:
    - The result of the agent's `run/2` function, typically `{:ok, output_map}` or `{:error, reason}`.
    - `{:error, :timeout}` if the call times out.
  """
  def run(server, input, timeout \\ @default_timeout) do
    GenServer.call(server, {:run, input}, timeout)
  rescue
    # General rescue clause
    e ->
      Logger.error("[Agent.Server] Run call failed: #{inspect(e)}")
      # Check if it was an Exit signal if specific handling is needed
      # if is_struct(e, Exit), do: {:error, {:server_exit, e}}, else: {:error, {:server_call_error, e}}
      {:error, {:server_call_error, e}}
  end

  # --- GenServer Callbacks ---

  @impl GenServer
  def init(agent_struct) do
    # Ensure the agent struct has a session_id for its lifetime
    session_id = Map.get(agent_struct, :session_id) || UUID.uuid4()
    initialized_agent = Map.put(agent_struct, :session_id, session_id)

    Logger.info(
      "Agent server started for #{inspect(initialized_agent.__struct__)} with session_id: #{session_id}"
    )

    {:ok, initialized_agent}
  end

  @impl GenServer
  def handle_call({:run, input}, _from, agent_struct) do
    # Generate a unique ID for this specific invocation
    invocation_id = UUID.uuid4()
    # Should always be set by init/1
    session_id = agent_struct.session_id

    # Inject invocation_id into the struct for run/2 context
    agent_struct_with_context = Map.put(agent_struct, :invocation_id, invocation_id)

    # Get the struct module
    struct_module = agent_struct_with_context.__struct__

    # Check if the struct module has a __agent_module__/0 function, use that if available
    agent_module_name =
      if function_exported?(struct_module, :__agent_module__, 0) do
        struct_module.__agent_module__()
      else
        # Otherwise, derive the agent module name (as before)
        struct_module
        |> Module.split()
        |> Enum.drop(-1)
        |> Module.concat()
      end

    Logger.debug(
      "Running agent #{inspect(agent_module_name)} [Session: #{session_id}, Invocation: #{invocation_id}]"
    )

    # Create context map for callbacks and telemetry
    context = %{
      agent_module: agent_module_name,
      agent_name: Map.get(agent_struct, :name),
      session_id: session_id,
      invocation_id: invocation_id
    }

    # Use telemetry span to track agent run
    Adk.Telemetry.span(
      [:adk, :agent, :run],
      context,
      fn ->
        # Execute before_run callbacks
        case Adk.Callback.execute(:before_run, input, context) do
          {:ok, modified_input} ->
            # Continue with modified input
            try do
              # Delegate to the specific *agent module's* run function
              result = agent_module_name.run(agent_struct_with_context, modified_input)

              # Execute after_run callbacks with the result
              final_result =
                case result do
                  {:ok, output} ->
                    case Adk.Callback.execute(:after_run, output, context) do
                      {:ok, modified_output} -> {:ok, modified_output}
                      {:halt, final_output} -> {:ok, final_output}
                    end

                  error_result ->
                    # Execute on_error callbacks if there was an error
                    case Adk.Callback.execute(:on_error, error_result, context) do
                      {:ok, modified_error} -> modified_error
                      {:halt, final_error} -> final_error
                    end
                end

              # Restore original agent_struct state (without invocation_id) for the GenServer state
              {:reply, final_result, agent_struct}
            rescue
              e ->
                error_message =
                  "Error during agent run [Session: #{session_id}, Invocation: #{invocation_id}]: #{inspect(e)}"

                Logger.error(error_message)

                # Execute on_error callbacks
                error_data = {:error, {:agent_execution_error, e}}

                final_error =
                  case Adk.Callback.execute(:on_error, error_data, context) do
                    {:ok, modified_error} -> modified_error
                    {:halt, final_error} -> final_error
                  end

                # Always wrap errors in an agent_execution_error, regardless of their original format
                # This ensures a consistent format that tests can assert against
                {:reply, final_error, agent_struct}
            end

          {:halt, halt_result} ->
            # Before_run callback halted the chain, return the result directly
            {:reply, {:ok, halt_result}, agent_struct}
        end
      end
    )
  end

  # --- Default Handlers ---

  @impl GenServer
  def handle_call(request, _from, state) do
    Logger.warning("Unhandled call in Adk.Agent.Server: #{inspect(request)}")
    {:reply, {:error, :unknown_call, request}, state}
  end

  @impl GenServer
  def handle_cast(msg, state) do
    Logger.warning("Unhandled cast in Adk.Agent.Server: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(info, state) do
    Logger.warning("Unhandled info in Adk.Agent.Server: #{inspect(info)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("Agent server terminating. Reason: #{inspect(reason)}, State: #{inspect(state)}")
    :ok
  end
end
