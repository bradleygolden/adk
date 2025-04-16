defmodule Adk.Agents.LLM do
  @moduledoc """
  An LLM-driven agent that uses a language model to determine its actions.

  This agent uses an LLM to decide which tools to call and how to respond to input.
  """
  use GenServer
  @behaviour Adk.Agent
  
  @impl Adk.Agent
  def run(agent, input), do: Adk.Agent.run(agent, input)

  @impl GenServer
  def init(config) do
    # Validate required config
    case validate_config(config) do
      :ok ->
        # Initialize state
        state = %{
          name: Map.get(config, :name),
          tools: Map.get(config, :tools, []),
          llm_provider: Map.get(config, :llm_provider, :mock),
          llm_options: Map.get(config, :llm_options, %{}),
          system_prompt: Map.get(config, :system_prompt, default_system_prompt()),
          memory: %{messages: []},
          config: config
        }

        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl GenServer
  def handle_call({:run, input}, _from, state) do
    # Process the user input using the LLM agent
    new_state = add_message(state, "user", input)

    case process_with_llm(new_state) do
      {:ok, response, final_state} ->
        # Return the response and updated state
        {:reply, {:ok, %{output: response}}, final_state}

      {:error, reason, final_state} ->
        {:reply, {:error, reason}, final_state}
    end
  end

  # Private functions

  defp validate_config(config) do
    cond do
      !is_map(config) ->
        {:error, "Config must be a map"}

      true ->
        :ok
    end
  end

  defp process_with_llm(state) do
    # First, check if tools are provided
    available_tools = get_available_tools(state.tools)

    # Prepare the conversation history
    messages = prepare_messages(state, available_tools)

    # Get response from LLM
    case Adk.LLM.chat(state.llm_provider, messages, state.llm_options) do
      {:ok, response} ->
        # Parse the response to see if it contains a tool call
        case parse_response(response.content) do
          {:tool_call, tool_name, params} ->
            # Execute the tool
            case execute_tool(tool_name, params, state) do
              {:ok, tool_result, tool_state} ->
                # Add the tool result to the conversation
                tool_state = add_message(tool_state, "assistant", response.content)
                tool_state = add_message(tool_state, "function", tool_result, %{name: tool_name})

                # Process again with the tool result
                process_with_llm(tool_state)

              {:error, reason, error_state} ->
                # Add the error to the conversation
                error_state = add_message(error_state, "assistant", response.content)

                error_state =
                  add_message(error_state, "function", "Error: #{reason}", %{name: tool_name})

                # Process again with the error
                process_with_llm(error_state)
            end

          {:response, content} ->
            # Just a normal response, no tool call
            new_state = add_message(state, "assistant", content)
            {:ok, content, new_state}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp get_available_tools(tool_names) do
    # Get all registered tools
    all_tools = Adk.list_tools()

    # Filter to just the requested tools if provided
    if is_list(tool_names) && !Enum.empty?(tool_names) do
      tool_names
      |> Enum.map(&String.to_atom/1)
      |> Enum.filter(fn name ->
        Enum.any?(all_tools, fn module ->
          module.definition().name == Atom.to_string(name)
        end)
      end)
      |> Enum.map(fn name ->
        Enum.find(all_tools, fn module ->
          module.definition().name == Atom.to_string(name)
        end)
      end)
    else
      all_tools
    end
  end

  defp prepare_messages(state, available_tools) do
    # Start with the system prompt
    system_message = %{
      role: "system",
      content: state.system_prompt <> "\n\nAvailable tools:\n#{format_tools(available_tools)}"
    }

    # Add the conversation history
    [system_message | state.memory.messages]
  end

  defp format_tools(tools) do
    tools
    |> Enum.map(fn tool_module ->
      definition = tool_module.definition()

      """
      #{definition.name}: #{definition.description}
      Parameters: #{inspect(definition.parameters)}
      """
    end)
    |> Enum.join("\n\n")
  end

  defp parse_response(content) do
    # Look for tool call patterns in the response
    # This is a simple regex-based approach, in a real implementation
    # you might want something more sophisticated

    tool_call_regex = ~r/call_tool\("([^"]+)",\s*(\{[^}]+\})\)/

    case Regex.run(tool_call_regex, content) do
      [_, tool_name, params_json] ->
        # Try to parse the JSON params
        case Jason.decode(params_json) do
          {:ok, params} ->
            {:tool_call, tool_name, params}

          {:error, error} ->
            # Log the error for debugging
            IO.puts("JSON parse error: #{inspect(error)}, for params: #{params_json}")
            # If JSON parsing fails, just return the response
            {:response, content}
        end

      nil ->
        # No tool call found
        {:response, content}
    end
  end

  defp execute_tool(tool_name, params, state) do
    case Adk.Tool.execute(String.to_atom(tool_name), params) do
      {:ok, result} ->
        # Store the result in memory
        tool_results = Map.get(state.memory, :tool_results, %{})
        updated_tool_results = Map.put(tool_results, tool_name, result)
        new_memory = Map.put(state.memory, :tool_results, updated_tool_results)
        new_state = Map.put(state, :memory, new_memory)

        {:ok, result, new_state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp add_message(state, role, content, metadata \\ %{}) do
    # Create the new message
    new_message = Map.merge(%{role: role, content: content}, metadata)

    # Add it to the state
    updated_messages = state.memory.messages ++ [new_message]
    updated_memory = Map.put(state.memory, :messages, updated_messages)

    # Update state
    %{state | memory: updated_memory}
  end

  defp default_system_prompt do
    """
    You are a helpful AI assistant. You have access to a set of tools that you can use to answer the user's questions.

    When you want to use a tool, respond with:
    call_tool("tool_name", {"param1": "value1", "param2": "value2"})

    For example:
    call_tool("weather", {"location": "New York"})

    After you call a tool, you'll receive the result and can continue the conversation.
    If you can answer the user's question without using a tool, just respond normally.
    """
  end

  def start_link({config, opts}) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  def start_link(config) when is_map(config) do
    GenServer.start_link(__MODULE__, config, [])
  end
end
