defmodule Adk.Agents.LLMTest do
  use ExUnit.Case, async: true

  setup do
    # Only register the test tool; registries and supervisors are started by the application
    Adk.register_tool(Adk.AgentsTest.TestTool)
    :ok
  end

  # Setup block to clear mock state before each test
  setup do
    Adk.Test.MockLLMStateAgent.clear_response()
    :ok
  end

  describe "LLM execution" do
    test "processes input using an LLM and executes tool calls" do
      # Configure the LLM agent to use our mock provider
      agent_config = %{
        name: :llm_test,
        tools: ["test_tool"],
        # Use the actual mock provider module
        llm_provider: Adk.Test.MockLLMProvider
        # llm_options are not needed when using the mock directly
      }

      {:ok, agent} = Adk.create_agent(:llm, agent_config)

      # Set the mock response to simulate a tool call
      Adk.Test.MockLLMStateAgent.set_response(
        "call_tool(\"test_tool\", {\"input\": \"from_llm\"})"
      )

      {:ok, result} = Adk.run(agent, "Can you process this for me?")

      # Assert that the tool was called and returned its result
      assert result.output.output == "Processed: from_llm"
      assert result.output.status == :tool_call_completed
    end

    test "handles direct responses without tool calls" do
      agent_config = %{
        name: :llm_direct_test,
        tools: ["test_tool"],
        # Use the actual mock provider module
        llm_provider: Adk.Test.MockLLMProvider
        # llm_options are not needed when using the mock directly
      }

      {:ok, agent} = Adk.create_agent(:llm, agent_config)

      # Set the mock response to simulate a direct answer
      direct_answer = "I can answer this directly without using any tools."
      Adk.Test.MockLLMStateAgent.set_response(direct_answer)

      {:ok, result} = Adk.run(agent, "What's 2+2?")

      # Assert that the direct answer from the LLM is returned
      assert result.output.output == direct_answer
      assert result.output.status == :completed
    end

    test "llm provider returns an error" do
      agent_config = %{
        name: :llm_error_test,
        tools: ["test_tool"],
        llm_provider: Adk.Test.MockLLMProvider
      }

      {:ok, agent} = Adk.create_agent(:llm, agent_config)
      # Simulate provider error
      Adk.Test.MockLLMStateAgent.set_response({:error, :provider_failed})
      assert {:error, :provider_failed} = Adk.run(agent, "trigger error")
    end

    test "tool call fails" do
      agent_config = %{
        name: :llm_tool_fail_test,
        tools: ["nonexistent_tool"],
        llm_provider: Adk.Test.MockLLMProvider
      }

      {:ok, agent} = Adk.create_agent(:llm, agent_config)
      # Simulate a tool call to a tool that doesn't exist
      Adk.Test.MockLLMStateAgent.set_response(
        "call_tool(\"nonexistent_tool\", {\"input\": \"fail\"})"
      )

      assert {:error, {:tool_execution_failed, {:tool_not_found, :nonexistent_tool}}} =
               Adk.run(agent, "fail tool call")
    end

    test "handles empty input" do
      agent_config = %{
        name: :llm_empty_input_test,
        tools: ["test_tool"],
        llm_provider: Adk.Test.MockLLMProvider
      }

      {:ok, agent} = Adk.create_agent(:llm, agent_config)
      Adk.Test.MockLLMStateAgent.set_response("Empty input handled.")
      {:ok, result} = Adk.run(agent, "")
      assert result.output.output == "Empty input handled."
    end
  end
end
