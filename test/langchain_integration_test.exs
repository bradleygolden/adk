defmodule Adk.LangchainIntegrationTest do
  use ExUnit.Case
  
  # Define a test tool for use with the agent
  defmodule TestTool do
    use Adk.Tool

    @impl true
    def definition do
      %{
        name: "test_tool",
        description: "A test tool for testing",
        parameters: %{
          input: %{
            type: "string",
            description: "The input to the tool"
          }
        }
      }
    end

    @impl true
    def execute(%{"input" => input}) do
      {:ok, "Processed: #{input}"}
    end
  end

  setup do
    Adk.register_tool(TestTool)
    :ok
  end

  test "langchain provider config has expected structure" do
    config = Adk.LLM.Providers.Langchain.config()
    assert config.name == "langchain"
    assert is_binary(config.description)
  end
  
  test "agent supervisor recognizes langchain agent type" do
    module = Adk.AgentSupervisor.get_agent_module(:langchain)
    assert module == Adk.Agents.Langchain
  end
end