defmodule Adk.Agents.LLM do
  @moduledoc """
  An LLM-driven agent that uses a language model to determine its actions.

  This agent uses an LLM to decide which tools to call and how to respond to input.
  """
  use GenServer
  alias Adk.Memory
  require UUID
  require Logger
  @behaviour Adk.Agent

  alias Adk.LLM

  # --- Structs ---

  defmodule Config do
    @moduledoc """
    Configuration struct for the LLM Agent.
    """
    @enforce_keys [:name, :llm_provider]
    defstruct [
      :name,
      :llm_provider,
      tools: [],
      llm_options: %{},
      # Default set later if not provided
      system_prompt: nil,
      input_schema: nil,
      output_schema: nil,
      output_key: nil,
      generate_content_config: %{},
      include_contents: :default,
      prompt_builder: Adk.Agents.Llm.DefaultPromptBuilder,
      memory_service: :in_memory
    ]
  end

  defmodule State do
    @moduledoc """
    Internal state struct for the LLM Agent GenServer.
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

  # --- GenServer Callbacks ---

  @impl GenServer
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
  @spec handle_call({:run, any()}, any(), State.t()) ::
          {:reply, {:ok, map()} | {:error, term()}, State.t()}
  def handle_call({:run, input}, _from, %State{} = state) do
    session_id = state.current_session_id || "session_#{System.unique_integer([:positive])}"
    state = Map.put(state, :current_session_id, session_id)
    prompt_builder_mod = state.config.prompt_builder

    with {:ok, processed_input} <- process_input(input, state.config.input_schema),
         {:ok, history} <-
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
      # Format the response based on whether it's a tool call or direct response
      response = %{
        output: %{
          output: llm_response.content,
          status: if(llm_response.tool_calls, do: :tool_call_completed, else: :completed)
        }
      }

      {:reply, {:ok, response}, state}
    else
      {:error, {:prompt_build_error, reason}} ->
        {:reply, {:error, {:prompt_build_error, reason}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # --- Private Functions ---

  # Config Validation
  defp validate_and_build_config(config_map) do
    # 1. Check for required keys first
    required_keys = [:name, :llm_provider]
    missing_keys = Enum.filter(required_keys, &(!Map.has_key?(config_map, &1)))

    if !Enum.empty?(missing_keys) do
      {:error, {:invalid_config, :missing_keys, missing_keys}}
    else
      # 2. Set defaults if needed
      config_with_defaults = Map.put_new(config_map, :system_prompt, default_system_prompt())

      config_with_defaults =
        Map.put_new(config_with_defaults, :prompt_builder, Adk.Agents.Llm.DefaultPromptBuilder)

      # 3. Attempt struct conversion (should succeed for required keys now)
      try do
        config = struct!(Config, config_with_defaults)

        # 4. Perform further validations
        with :ok <- validate_llm_provider(config.llm_provider),
             :ok <- validate_tools(config.tools),
             :ok <- validate_prompt_builder(config.prompt_builder) do
          {:ok, config}
        else
          # Capture the first validation error
          {:error, reason} -> {:error, reason}
        end
      rescue
        # Catch ArgumentError from struct! if types are wrong for non-enforced keys
        ArgumentError ->
          {:error, {:invalid_config, :struct_conversion_failed, config_with_defaults}}

        # Catch any other unexpected error during struct creation/validation
        e ->
          {:error, {:invalid_config, :unexpected_error, e}}
      end
    end
  end

  defp validate_llm_provider(provider) when is_atom(provider), do: :ok

  defp validate_llm_provider(other),
    do: {:error, {:invalid_config, :invalid_llm_provider_type, other}}

  defp validate_tools(tools) when is_list(tools), do: :ok
  defp validate_tools(other), do: {:error, {:invalid_config, :invalid_tools_type, other}}

  defp validate_prompt_builder(module) when is_atom(module) do
    # Check if the module implements the behaviour
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

  defp validate_prompt_builder(other) do
    {:error, {:invalid_config, :invalid_prompt_builder_type, other}}
  end

  # --- Input Processing ---

  # No input schema, pass through
  defp process_input(input, nil), do: {:ok, input}

  defp process_input(input, schema_module) when is_binary(input) do
    case JSON.decode(input) do
      {:ok, decoded_map} ->
        case struct(schema_module, decoded_map) do
          # Successfully created struct
          %_{} = valid_struct -> {:ok, valid_struct}
          _ -> {:error, "Input JSON does not match schema #{inspect(schema_module)}"}
        end

      {:error, _} ->
        {:error, "Input is not valid JSON"}
    end
  end

  defp process_input(_input, schema_module) do
    {:error,
     "Input must be a JSON string when input_schema #{inspect(schema_module)} is specified"}
  end

  # Convert validated struct back for history if needed
  defp input_to_string(%_{} = struct), do: JSON.encode!(struct)
  defp input_to_string(other), do: to_string(other)

  # --- Conversation History ---

  # include_contents: :none
  defp get_conversation_history(_service, _session_id, :none), do: {:ok, []}

  defp get_conversation_history(service, session_id, _include_contents) do
    # Fetch and format history from memory service
    # This needs implementation based on Adk.Memory structure
    Logger.debug("Fetching history for session #{session_id} with service #{inspect(service)}")
    # Placeholder:
    case Memory.get_sessions(service, session_id) do
      {:ok, sessions} ->
        # Assuming sessions are stored chronologically and need mapping to {:role, :content} format
        history =
          Enum.map(sessions, fn session_data ->
            # Adapt this based on actual memory storage format
            Map.get(session_data, :message, %{role: "unknown", content: inspect(session_data)})
          end)

        {:ok, history}

      # Default to empty if fetch fails or no history
      _ ->
        {:ok, []}
    end
  end

  # --- Core LLM/Tool Execution Logic ---

  defp execute_llm_or_tools(messages, state) do
    # No output schema - standard flow with potential tool usage
    Logger.debug("[Agent #{state.config.name}] No output schema, proceeding with standard flow.")
    # Initial LLM call to determine if a tool is needed
    case call_llm(messages, state) do
      {:ok, %{content: content}} ->
        # Parse the tool call from the content
        case parse_tool_call(content) do
          {:ok, tool_name, tool_args} ->
            # Execute the tool
            case Adk.execute_tool(String.to_atom(tool_name), tool_args) do
              {:ok, tool_result} ->
                {:ok,
                 %{content: tool_result, tool_calls: [%{name: tool_name, arguments: tool_args}]}}

              {:error, reason} ->
                {:error, {:tool_execution_failed, reason}}
            end

          {:error, _reason} ->
            # Not a tool call, treat as direct response
            {:ok, %{content: content, tool_calls: nil}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_tool_call(content) do
    # Extract tool name and arguments from content like: call_tool("test_tool", {"input": "from_llm"})
    case Regex.run(~r/call_tool\("([^"]+)",\s*(\{[^}]+\})\)/, content) do
      [_, tool_name, args_json] ->
        case JSON.decode(args_json) do
          {:ok, args} -> {:ok, tool_name, args}
          {:error, reason} -> {:error, {:invalid_json, reason}}
        end

      _ ->
        {:error, :invalid_tool_call_format}
    end
  end

  # --- LLM Interaction ---

  defp call_llm(messages, state) do
    Logger.debug(
      "[Agent #{state.config.name}] Calling LLM #{state.config.llm_provider} with messages: #{inspect(messages)}"
    )

    case LLM.chat(state.config.llm_provider, messages, state.config.llm_options) do
      {:ok, %{content: content, tool_calls: tool_calls}} ->
        {:ok, %{content: content, tool_calls: tool_calls}}

      {:ok, %{content: content}} ->
        {:ok, %{content: content, tool_calls: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Default System Prompt ---

  defp default_system_prompt do
    """
    You are a helpful AI assistant. You have access to a set of tools that you can use to answer the user's questions.

    To use a tool, the response MUST be a JSON object containing a `tool_calls` list.
    Each item in the list should be an object with `id`, `type: "function"`, and `function` fields.
    The `function` field should contain `name` (the tool name) and `arguments` (a JSON string of parameters).

    Example of a response using a tool:
    ```json
    {
      "tool_calls": [
        {
          "id": "call_abc123",
          "type": "function",
          "function": {
            "name": "get_weather",
            "arguments": "{\"location\": \"New York\", \"unit\": \"fahrenheit\"}"
          }
        }
      ]
    }
    ```

    If you need to call multiple tools, include multiple objects in the `tool_calls` list.
    If you can answer the user's question without using a tool, respond with your answer directly as plain text. Do NOT wrap plain text responses in JSON.
    Only respond with the JSON structure when you intend to call one or more tools.
    """
  end

  # --- Start Link ---

  # Allow passing GenServer options
  def start_link({config_map, opts}) when is_map(config_map) and is_list(opts) do
    GenServer.start_link(__MODULE__, config_map, opts)
  end

  # Default start_link without options
  def start_link(config_map) when is_map(config_map) do
    GenServer.start_link(__MODULE__, config_map, [])
  end
end
