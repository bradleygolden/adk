defmodule Adk.Agents.Langchain do
  @moduledoc """
  Implements a LangChain-driven workflow agent per the Adk pattern.

  This agent integrates with the LangChain Elixir library, using the `Adk.LLM.Providers.Langchain` provider. It supports Adk tools, schemas, and memory integration. Implements the `Adk.Agent` behaviour.

  Extension points:
  - Add new tool call or message handling logic by extending `handle_tool_calls/3` or `handle_direct_response/2`.
  - Customize prompt building by providing a custom prompt builder module.
  - See https://google.github.io/adk-docs/Agents/Workflow-agents for design rationale.
  """
  use GenServer
  alias Adk.Memory
  require UUID
  require Logger
  @behaviour Adk.Agent

  alias Adk.{
    LLM
  }

  # --- Structs (Mirrors LLM Agent) ---

  defmodule Config do
    @moduledoc """
    Configuration struct for the Langchain Agent.
    """
    # Requires llm_options for provider details
    @enforce_keys [:name, :llm_options]
    defstruct [
      :name,
      # llm_options must contain :provider, :api_key, :model etc.
      # The provider should typically be :openai or :anthropic for Langchain
      :llm_options,
      tools: [],
      system_prompt: nil,
      input_schema: nil,
      output_schema: nil,
      output_key: nil,
      # Use the Langchain provider directly
      llm_provider: Adk.LLM.Providers.Langchain,
      # May not be directly used by Langchain provider
      generate_content_config: %{},
      include_contents: :default,
      # Configurable prompt builder
      prompt_builder: DefaultPromptBuilder,
      # Configurable memory service
      memory_service: :in_memory
    ]
  end

  defmodule State do
    @moduledoc """
    Internal state struct for the Langchain Agent GenServer.
    """
    @enforce_keys [:session_id, :config]
    defstruct [
      :session_id,
      # Holds the %Config{} struct
      :config,
      conversation_history: [],
      current_session_id: nil,
      session_state: %{}
    ]
  end

  # --- Agent API ---

  @impl Adk.Agent
  def run(agent, input), do: Adk.Agent.run(agent, input)

  @impl Adk.Agent
  def handle_request(_input, state), do: {:ok, %{output: "Not implemented"}, state}

  # --- GenServer Callbacks ---

  @impl GenServer
  def init({config_map, _opts}) when is_map(config_map), do: init(config_map)

  def init(config_map) when is_map(config_map) do
    with {:ok, config} <- validate_and_build_config(config_map) do
      session_id = UUID.uuid4()
      state = %State{session_id: session_id, config: config}
      {:ok, state}
    else
      # Propagate descriptive error tuple
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:run, input}, _from, %State{} = state) do
    session_id = state.current_session_id || "session_#{System.unique_integer([:positive])}"
    state = Map.put(state, :current_session_id, session_id)

    # --- Input Validation First ---
    with {:ok, processed_input} <- process_input(input, state.config.input_schema) do
      # --- If Input is Valid, Proceed ---
      prompt_builder_mod = state.config.prompt_builder

      with {:ok, history} <-
             get_conversation_history(
               state.config.memory_service,
               session_id,
               state.config.include_contents
             ),
           state <-
             Map.put(
               state,
               :conversation_history,
               history ++ [%{role: "user", content: input_to_string(processed_input)}]
             ),
           {:ok, messages} <- prompt_builder_mod.build_messages(state),
           {:ok, llm_response} <- execute_llm_or_tools(messages, state) do
        # --- Format Success Response ---
        status =
          cond do
            state.config.output_schema && is_struct(llm_response.content) -> :schema_validated
            llm_response.tool_calls -> :tool_call_completed
            true -> :completed
          end

        response = %{output: %{output: llm_response.content, status: status}}
        state = update_memory(state, %{role: "assistant", content: llm_response.content})
        {:reply, {:ok, response}, state}

        # --- Handle Errors During Execution Flow ---
      else
        {:error, reason} ->
          Logger.error(
            "[Agent #{state.config.name}] Run failed during history/prompt/execution: #{inspect(reason)}"
          )

          {:reply, {:error, reason}, state}
      end

      # --- Handle Input Validation Error ---
    else
      {:error, reason} ->
        Logger.error(
          "[Agent #{state.config.name}] Run failed during input processing: #{inspect(reason)}"
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  # --- Private Functions (Adapted from LLM Agent) ---

  # --- Config Validation ---
  defp validate_and_build_config(config_map) do
    # 1. Check required keys (name is implicit, llm_options required)
    required_keys = [:name, :llm_options]
    missing_keys = Enum.filter(required_keys, &(!Map.has_key?(config_map, &1)))

    if !Enum.empty?(missing_keys) do
      {:error, {:invalid_config, :missing_keys, missing_keys}}
    else
      # 2. Set defaults
      config_with_defaults = Map.put_new(config_map, :system_prompt, default_system_prompt())

      config_with_defaults =
        Map.put(config_with_defaults, :llm_provider, Adk.LLM.Providers.Langchain)

      config_with_defaults =
        Map.put_new(config_with_defaults, :prompt_builder, Adk.Agents.Llm.LangchainPromptBuilder)

      config_with_defaults = Map.put_new(config_with_defaults, :memory_service, :in_memory)
      config_with_defaults = Map.put_new(config_with_defaults, :include_contents, :default)
      config_with_defaults = Map.put_new(config_with_defaults, :tools, [])

      # 3. Validate llm_options specifically for Langchain provider needs
      case validate_llm_options(config_with_defaults.llm_options) do
        :ok ->
          # 4. Attempt struct conversion
          try do
            config = struct!(Config, config_with_defaults)

            # 5. Perform further general validations (tools, prompt_builder)
            with :ok <- validate_tools(config.tools),
                 :ok <- validate_prompt_builder(config.prompt_builder) do
              {:ok, config}
            else
              # Propagate validation error
              {:error, reason} -> {:error, reason}
            end
          rescue
            ArgumentError ->
              {:error, {:invalid_config, :struct_conversion_failed, config_with_defaults}}

            e ->
              {:error, {:invalid_config, :unexpected_error, e}}
          end

        {:error, reason} ->
          # Propagate llm_options validation error
          {:error, reason}
      end
    end
  end

  # Validation specific to Langchain llm_options
  defp validate_llm_options(nil), do: {:error, {:invalid_config, :missing_llm_options}}

  defp validate_llm_options(llm_options) when is_map(llm_options) do
    # Langchain provider requires :api_key, :provider (:openai, :anthropic etc.), :model
    with :ok <-
           validate_required_option(llm_options, :api_key, "API key is required in llm_options"),
         :ok <-
           validate_required_option(
             llm_options,
             :provider,
             "Provider (:openai, :anthropic) is required in llm_options"
           ),
         :ok <- validate_required_option(llm_options, :model, "Model is required in llm_options") do
      :ok
    else
      # Return the specific error tuple
      {:error, error_message} -> {:error, {:invalid_config, :missing_llm_option, error_message}}
    end
  end

  defp validate_llm_options(other),
    do: {:error, {:invalid_config, :invalid_llm_options_type, other}}

  # General required option checker
  defp validate_required_option(options, key, error_message) do
    if Map.has_key?(options, key) and !is_nil(Map.get(options, key)),
      do: :ok,
      else: {:error, error_message}
  end

  # General tool and prompt builder validation (same as LLM agent)
  defp validate_tools(tools) when is_list(tools), do: :ok
  defp validate_tools(other), do: {:error, {:invalid_config, :invalid_tools_type, other}}

  defp validate_prompt_builder(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _} ->
        if function_exported?(module, :build_messages, 1) do
          :ok
        else
          {:error,
           {:invalid_config, :prompt_builder_missing_callback, {module, :build_messages, 1}}}
        end

      {:error, reason} ->
        {:error, {:invalid_config, :prompt_builder_module_not_loaded, {module, reason}}}
    end
  end

  defp validate_prompt_builder(other),
    do: {:error, {:invalid_config, :invalid_prompt_builder_type, other}}

  # --- Input Processing --- (Same as LLM Agent)
  defp process_input(input, nil), do: {:ok, input}

  defp process_input(input, schema_module) when is_binary(input) do
    case JSON.decode(input) do
      {:ok, decoded_map} ->
        # Convert string keys to atoms for struct creation
        decoded_map_with_atoms =
          for {key, val} <- decoded_map, into: %{}, do: {String.to_existing_atom(key), val}

        # Use struct! to enforce required keys
        try do
          case struct!(schema_module, decoded_map_with_atoms) do
            %_{} = valid_struct -> {:ok, valid_struct}
            _ -> {:error, {:schema_validation_failed, :input, input, schema_module}}
          end
        rescue
          KeyError -> {:error, {:schema_validation_failed, :input, input, schema_module}}
          ArgumentError -> {:error, {:schema_validation_failed, :input, input, schema_module}}
        end

      {:error, _} ->
        {:error, {:invalid_json_input, input}}
    end
  end

  defp process_input(_input, schema_module),
    do: {:error, {:invalid_input_type_for_schema, schema_module}}

  # Convert validated struct back for history if needed
  # Fallback to inspect if JSON encoding fails (e.g., protocol not derived/consolidated)
  defp input_to_string(%_{} = struct) do
    try do
      JSON.encode!(struct)
    rescue
      _ ->
        Logger.warning(
          "Failed to JSON encode struct for history, using inspect: #{inspect(struct)}"
        )

        inspect(struct)
    end
  end

  defp input_to_string(other), do: to_string(other)

  # --- Conversation History --- (Same as LLM Agent)
  defp get_conversation_history(_service, _session_id, :none), do: {:ok, []}

  defp get_conversation_history(service, session_id, _include_contents) do
    Logger.debug("[Agent #{session_id}] Fetching history with service #{inspect(service)}")

    Memory.get_history(service, session_id)
    |> case do
      {:ok, history_events} ->
        # Convert Adk.Event structs back to basic maps for the provider
        formatted_history =
          Enum.map(history_events, fn event ->
            # Simple format for now
            %{role: Atom.to_string(event.author), content: event.content}
          end)

        {:ok, formatted_history}

      # No history is fine
      {:error, {:session_not_found, _}} ->
        {:ok, []}

      # Propagate other errors
      {:error, reason} ->
        {:error, {:memory_fetch_failed, reason}}
    end
  end

  # --- Core LLM/Tool Execution Logic ---
  defp execute_llm_or_tools(messages, state) do
    Logger.debug("[Agent #{state.config.name}] Calling Langchain provider...")

    # Prepare options for the Langchain provider call
    llm_options = state.config.llm_options

    # Determine provider: prefer llm_options[:provider] if present, else fallback to state.config.llm_provider
    provider =
      case Map.get(llm_options, :provider) do
        nil -> Map.get(state.config, :llm_provider, :langchain)
        val -> val
      end

    # Call the provider via Adk.LLM facade
    case LLM.chat(provider, messages, Map.put(llm_options, :tools, state.config.tools)) do
      {:ok, %{content: content, tool_calls: tool_calls}} ->
        Logger.debug(
          "[Agent #{state.config.name}] Langchain response. Content: #{inspect(content)}, Tools: #{inspect(tool_calls)}"
        )

        if tool_calls && !Enum.empty?(tool_calls) do
          # Langchain provider returned tool calls
          handle_tool_calls(tool_calls, state, messages)
        else
          # Direct response or structured output (handle schema validation)
          handle_direct_response(content, state)
        end

      # Handle case where tool_calls might be nil
      {:ok, %{content: content}} ->
        handle_direct_response(content, state)

      {:error, reason} ->
        Logger.error("[Agent #{state.config.name}] Langchain provider failed: #{inspect(reason)}")
        {:error, {:llm_provider_error, reason}}
    end
  end

  # --- Tool Handling (Langchain specific potentially) ---
  defp handle_tool_calls(tool_calls, state, _original_messages) do
    Logger.debug(
      "[Agent #{state.config.name}] Handling Langchain tool calls: #{inspect(tool_calls)}"
    )

    # Assuming Langchain provider gives calls in OpenAI format:
    # [%{"id" => "call_xyz", "type" => "function", "function" => %{"name" => "tool_name", "arguments" => "{...}"}}]

    # Execute each tool call using Adk.ToolRegistry
    tool_results =
      Enum.map(tool_calls, fn tool_call ->
        # Ensure correct structure before accessing keys
        id = Map.get(tool_call, "id")
        function_map = Map.get(tool_call, "function")

        # Safely extract name and arguments, handling nil
        name = if function_map, do: Map.get(function_map, "name"), else: nil
        args_json = if function_map, do: Map.get(function_map, "arguments"), else: nil

        if id && name && args_json do
          case JSON.decode(args_json) do
            {:ok, args_map} ->
              # Basic context
              context = %{
                session_id: state.current_session_id,
                tool_call_id: id,
                invocation_id: state.session_id
              }

              case Adk.ToolRegistry.execute_tool(String.to_atom(name), args_map, context) do
                # Format for next LLM call
                {:ok, result} ->
                  %{tool_call_id: id, role: "tool", name: name, content: result}

                {:error, reason} ->
                  %{
                    tool_call_id: id,
                    role: "tool",
                    name: name,
                    content: "Error executing tool: #{inspect(reason)}"
                  }
              end

            {:error, reason} ->
              Logger.error(
                "[Agent #{state.config.name}] Failed to decode tool arguments JSON: #{inspect(reason)}, JSON: #{args_json}"
              )

              %{
                tool_call_id: id,
                role: "tool",
                name: name,
                content: "Error: Invalid arguments JSON received"
              }
          end
        else
          Logger.error(
            "[Agent #{state.config.name}] Received malformed tool call: #{inspect(tool_call)}"
          )

          # Decide how to handle malformed calls, maybe return an error message?
          # For now, returning a generic error message for this specific call
          %{
            tool_call_id: id || "unknown",
            role: "tool",
            name: name || "unknown",
            content: "Error: Malformed tool call received from LLM"
          }
        end
      end)

    # TODO: Resubmit tool results to LangChain for final answer.
    # This requires another call to LLM.chat with history + tool results.
    # For now, we'll just return the result of the first tool executed
    # This is a simplification and needs a proper multi-turn implementation.
    first_result_content =
      case List.first(tool_results) do
        nil -> "No tool result available."
        # Extract content from the first tool result event map
        result -> result.content
      end

    # Return first tool result for now
    {:ok, %{content: first_result_content, tool_calls: tool_calls}}
  end

  # --- Direct Response & Schema Handling ---
  defp handle_direct_response(content, state) do
    case state.config.output_schema do
      nil ->
        # No schema, just return the content
        {:ok, %{content: content, tool_calls: nil}}

      schema_module ->
        # Use our JsonProcessor to handle JSON parsing, extraction, and validation
        case Adk.JsonProcessor.process_json(content, schema_module) do
          {:ok, valid_struct} ->
            # Return validated struct
            {:ok, %{content: valid_struct, tool_calls: nil}}

          {:error, {:invalid_json, _}} ->
            Logger.error(
              "[Agent #{state.config.name}] Output is not valid JSON for schema: #{inspect(schema_module)}, Content: #{content}"
            )

            {:error, {:invalid_json_output, content}}

          {:error, {:schema_validation_failed, module, data}} ->
            Logger.error(
              "[Agent #{state.config.name}] Output failed schema validation: #{inspect(module)}, Content: #{inspect(data)}"
            )

            {:error, {:schema_validation_failed, :output, content, schema_module}}

          {:error, other_reason} ->
            Logger.error(
              "[Agent #{state.config.name}] Error processing JSON output: #{inspect(other_reason)}"
            )

            {:error, {:output_processing_failed, other_reason}}
        end
    end
  end

  # --- State and Memory Updates --- (Same as LLM Agent, slightly adapted)
  defp update_memory(state, %{role: role, content: content})
       when is_binary(content) or is_map(content) or is_struct(content) do
    # Add the new message event to memory
    session_id = state.current_session_id
    service = state.config.memory_service

    # Convert structs/maps to string for memory storage if needed, or handle appropriately
    content_for_memory = if is_struct(content), do: JSON.encode!(content), else: content

    # Use Adk.Event.new to create a proper event struct
    event_opts = %{
      session_id: session_id,
      # Link to overall agent invocation
      invocation_id: state.session_id,
      # Convert role back to atom for author
      author: String.to_atom(role),
      content: content_for_memory
      # tool_calls/tool_results could be added here if relevant
    }

    event = Adk.Event.new(event_opts)

    # Persist the event using Memory.add_message
    case Memory.add_message(service, session_id, event) do
      :ok ->
        # Update in-memory history (optional, as get_conversation_history refetches)
        # %{state | conversation_history: state.conversation_history ++ [new_message]}
        # Return unmodified state for now, relying on refetch
        state

      {:error, reason} ->
        Logger.error("[Agent #{state.config.name}] Failed to update memory: #{inspect(reason)}")
        # Continue even if memory update fails
        state
    end
  end

  # Ignore if not a message map
  defp update_memory(state, _other), do: state

  # --- Default System Prompt --- (Same as LLM Agent)
  defp default_system_prompt do
    """
    You are a helpful AI assistant. You have access to a set of tools that you can use to answer the user's questions.
    Follow the specific instructions provided by the underlying model (e.g., OpenAI function calling format) if you need to use a tool.
    """
  end

  # --- Start Link ---

  def start_link(config_map, opts \\ []) when is_map(config_map) do
    GenServer.start_link(__MODULE__, config_map, opts)
  end

  # Remove old helper functions no longer used
  # def create_langchain_agent(...) ...
  # defp process_with_langchain(...) ...
end
