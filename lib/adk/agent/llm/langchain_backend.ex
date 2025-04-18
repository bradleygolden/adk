defmodule Adk.Agent.LLM.LangchainBackend do
  @moduledoc """
  LangChain backend for LLM agents. Integrates with LangChain to perform reasoning, tool-calling, etc.
  """
  @behaviour Adk.Agent.LLM.Backend
  require Logger
  alias Adk.ToolRegistry
  require UUID

  @impl true
  def run(agent, input) do
    # For now, we're implementing a direct LLM call with tool execution
    # Later this would be integrated with actual LangChain

    session_id = agent.session_id || "langchain-session-#{UUID.uuid4()}"
    invocation_id = agent.invocation_id || "langchain-invocation-#{UUID.uuid4()}"

    # Build the prompt for the LLM
    with {:ok, history} <- get_history(session_id),
         {:ok, messages} <- build_prompt(agent, input, history),
         # Execute LLM call
         {:ok, llm_response} <- execute_llm(agent, messages) do
      # Handle tool calls if present
      case llm_response do
        %{tool_calls: tool_calls} when is_list(tool_calls) and tool_calls != [] ->
          handle_tool_calls(agent, llm_response, session_id, invocation_id)

        %{content: _content} ->
          # Direct response without tool calls
          {:ok, format_response(llm_response)}

        _ ->
          # Unexpected response format
          {:error, {:invalid_llm_response, llm_response}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Private Helper Functions ---

  defp get_history(_session_id) do
    # For now, just return empty history
    # In a real implementation, this would fetch from memory
    {:ok, []}
  end

  defp build_prompt(agent, input, history) do
    prompt_builder = agent.prompt_builder

    prompt_context = %{
      config: agent,
      history: history,
      input: input
    }

    try do
      prompt_builder.build_messages(prompt_context)
    rescue
      e -> {:error, {:prompt_build_error, e}}
    end
  end

  defp execute_llm(agent, messages) do
    llm_options = Map.put(agent.llm_options, :tools, format_tools_for_llm(agent.tools))

    # Create context for callbacks
    context = %{
      agent_name: agent.name,
      session_id: agent.session_id,
      invocation_id: agent.invocation_id,
      llm_provider: agent.llm_provider,
      model: agent.model,
      message_count: length(messages)
    }

    # Use telemetry to track LLM call
    Adk.Telemetry.span(
      [:adk, :llm, :call],
      context,
      fn ->
        # Execute before_llm_call callbacks
        case Adk.Callback.execute(:before_llm_call, messages, context) do
          {:ok, modified_messages} ->
            # Make the LLM call with possibly modified messages
            case agent.llm_provider.chat(modified_messages, llm_options) do
              {:ok, response} = _llm_result ->
                # Execute after_llm_call callbacks
                case Adk.Callback.execute(:after_llm_call, response, context) do
                  {:ok, modified_response} -> {:ok, modified_response}
                  {:halt, final_response} -> {:ok, final_response}
                end

              {:error, _reason} = error ->
                # Execute on_error callbacks
                case Adk.Callback.execute(:on_error, error, context) do
                  {:ok, modified_error} -> modified_error
                  {:halt, final_error} -> final_error
                end
            end

          {:halt, halt_result} ->
            # Before_llm_call callback halted the chain
            {:ok, halt_result}
        end
      end
    )
  end

  defp handle_tool_calls(agent, llm_response, session_id, invocation_id) do
    # Execute tools concurrently
    tool_results =
      llm_response.tool_calls
      |> Enum.map(
        &Task.async(fn -> execute_single_tool(agent, &1, session_id, invocation_id) end)
      )
      # Wait for each tool result
      |> Enum.map(&Task.await(&1, 60000))

    # Add tool results to the response and return
    response_with_tool_results =
      llm_response
      |> Map.put(:tool_results, tool_results)
      |> format_response()

    {:ok, response_with_tool_results}
  end

  defp execute_single_tool(agent, tool_call, session_id, invocation_id) do
    %{id: tool_call_id, name: tool_name, args: tool_args} = tool_call

    context = %{
      agent_name: agent.name,
      session_id: session_id,
      invocation_id: invocation_id,
      tool_call_id: tool_call_id,
      tool_name: tool_name
    }

    # Create tool call data for callbacks
    tool_call_data = %{
      tool_call_id: tool_call_id,
      name: tool_name,
      args: tool_args
    }

    # Use telemetry to track tool execution
    Adk.Telemetry.span(
      [:adk, :tool, :call],
      context,
      fn ->
        # Execute before_tool_call callbacks
        case Adk.Callback.execute(:before_tool_call, tool_call_data, context) do
          {:ok, modified_tool_data} ->
            # Execute the tool with possibly modified arguments
            tool_execution_context = %{
              session_id: session_id,
              invocation_id: invocation_id,
              tool_call_id: tool_call_id
            }

            tool_result =
              case ToolRegistry.execute_tool(
                     modified_tool_data.name,
                     modified_tool_data.args,
                     tool_execution_context
                   ) do
                {:ok, result} ->
                  tool_result = %{
                    tool_call_id: tool_call_id,
                    name: tool_name,
                    content: result,
                    status: :ok
                  }

                  # Execute after_tool_call callbacks
                  case Adk.Callback.execute(:after_tool_call, tool_result, context) do
                    {:ok, modified_result} -> modified_result
                    {:halt, final_result} -> final_result
                  end

                {:error, reason} ->
                  error_content = "Error executing tool '#{tool_name}': #{inspect(reason)}"

                  Logger.error(
                    "[#{session_id}/#{invocation_id}] Tool execution failed for #{tool_name} (#{tool_call_id}): #{inspect(reason)}"
                  )

                  error_result = %{
                    tool_call_id: tool_call_id,
                    name: tool_name,
                    content: error_content,
                    status: :error
                  }

                  # Execute on_error callbacks for tool failures
                  case Adk.Callback.execute(:on_error, error_result, context) do
                    {:ok, modified_error} -> modified_error
                    {:halt, final_error} -> final_error
                  end
              end

            tool_result

          {:halt, halt_result} ->
            # Before_tool_call callback halted the chain
            # Return a properly formatted tool result
            %{
              tool_call_id: tool_call_id,
              name: tool_name,
              content: halt_result,
              status: :ok
            }
        end
      end
    )
  end

  defp format_tools_for_llm(tools) when is_list(tools) do
    # Assuming a standard format for tools, adjust as needed
    %{function_declarations: tools}
  end

  defp format_response(llm_response) do
    Map.put(llm_response, :status, determine_status(llm_response))
  end

  defp determine_status(%{tool_results: results}) when is_list(results) and results != [] do
    :tool_results_returned
  end

  defp determine_status(%{tool_calls: calls}) when is_list(calls) and calls != [] do
    :tool_calls_requested
  end

  defp determine_status(_) do
    :completed
  end
end
