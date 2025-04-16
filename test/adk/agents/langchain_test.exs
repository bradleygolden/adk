defmodule Adk.Agents.LangchainTest do
  use ExUnit.Case, async: true
  alias Adk.BypassHelper
  alias Adk.Test.Schemas.{}

  @moduletag :capture_log

  describe "provider and supervisor integration" do
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

  describe "agent creation and configuration" do
    test "accepts valid configuration with openai provider" do
      valid_config = %{
        name: :test_langchain_agent_openai,
        llm_options: %{
          provider: :openai,
          model: "gpt-3.5-turbo",
          api_key: "test-api-key"
        }
      }

      assert {:ok, pid} = Adk.create_agent(:langchain, valid_config)
      assert is_pid(pid)

      # Clean up
      Process.exit(pid, :normal)
    end

    test "rejects configuration without llm_options" do
      invalid_config = %{
        name: :test_langchain_agent_invalid
      }

      assert {:error, {:invalid_config, :missing_keys, [:llm_options]}} =
               Adk.create_agent(:langchain, invalid_config)
    end

    test "rejects configuration with empty llm_options map" do
      invalid_config = %{
        name: :test_langchain_agent_empty_llm,
        llm_options: %{}
      }

      assert {:error,
              {:invalid_config, :missing_llm_option, "API key is required in llm_options"}} =
               Adk.create_agent(:langchain, invalid_config)
    end

    test "rejects configuration with nil llm_options" do
      invalid_config = %{
        name: :test_langchain_agent_nil_llm,
        llm_options: nil
      }

      assert {:error, {:invalid_config, :missing_llm_options}} =
               Adk.create_agent(:langchain, invalid_config)
    end

    test "rejects configuration with missing required fields" do
      # Missing api_key
      config1 = %{
        name: :test_langchain_agent_missing_api_key,
        llm_options: %{provider: :openai, model: "gpt-3.5-turbo"}
      }

      assert {:error,
              {:invalid_config, :missing_llm_option, "API key is required in llm_options"}} =
               Adk.create_agent(:langchain, config1)

      # Missing provider
      config2 = %{
        name: :test_langchain_agent_missing_provider,
        llm_options: %{api_key: "test-key", model: "gpt-3.5-turbo"}
      }

      assert {:error,
              {:invalid_config, :missing_llm_option,
               "Provider (:openai, :anthropic) is required in llm_options"}} =
               Adk.create_agent(:langchain, config2)

      # Missing model
      config3 = %{
        name: :test_langchain_agent_missing_model,
        llm_options: %{provider: :openai, api_key: "test-key"}
      }

      assert {:error, {:invalid_config, :missing_llm_option, "Model is required in llm_options"}} =
               Adk.create_agent(:langchain, config3)
    end
  end

  describe "API integration" do
    setup do
      bypass = Bypass.open()
      Application.put_env(:langchain, :openai_key, fn -> "dummy-key" end)
      bypass_url = BypassHelper.get_bypass_url(bypass) <> "/v1/chat/completions"
      {:ok, bypass: bypass, bypass_url: bypass_url}
    end

    test "processes input with LangChain successfully", %{
      bypass: bypass,
      bypass_url: bypass_url
    } do
      BypassHelper.expect_langchain_request(
        bypass,
        "POST",
        "/v1/chat/completions",
        "Test response from LangChain"
      )

      config = %{
        name: "test_agent_api_success_run",
        llm_options: %{
          endpoint: bypass_url,
          model: "gpt-3.5-turbo",
          temperature: 0.7,
          api_key: "dummy-key",
          provider: :openai
        }
      }

      {:ok, agent} = Adk.create_agent(:langchain, config)

      assert {:ok, %{output: %{output: "Test response from LangChain", status: :completed}}} =
               Adk.run(agent, "Test input")
    end

    test "handles LangChain API errors", %{bypass: bypass, bypass_url: bypass_url} do
      error_response = %{"error" => %{"message" => "API error occurred"}}

      BypassHelper.expect_langchain_error(
        bypass,
        "POST",
        "/v1/chat/completions",
        400,
        error_response
      )

      config = %{
        name: "test_agent_api_error_run",
        llm_options: %{
          endpoint: bypass_url,
          model: "gpt-3.5-turbo",
          temperature: 0.7,
          api_key: "dummy-key",
          provider: :openai
        }
      }

      {:ok, agent} = Adk.create_agent(:langchain, config)

      assert {:error, {:llm_provider_error, %LangChain.LangChainError{message: msg}}} =
               Adk.run(agent, "Test input")

      assert msg =~ "API error occurred"
    end

    test "handles connection errors to custom endpoint", %{bypass: bypass} do
      # Close the bypass to simulate a connection error
      Bypass.down(bypass)

      config = %{
        name: "test_agent_conn_error_run",
        llm_options: %{
          endpoint: BypassHelper.get_bypass_url(bypass) <> "/v1/chat/completions",
          api_key: "test_key",
          provider: :openai,
          model: "gpt-3.5-turbo"
        }
      }

      {:ok, agent} = Adk.create_agent(:langchain, config)
      result = Adk.run(agent, "Hello")
      # Assert correct error structure (match the logged error)
      assert match?(
               {:error,
                {:llm_provider_error,
                 "Failed to run LLMChain: %CaseClauseError{term: {:error, %Req.TransportError{reason: :econnrefused}}}"}},
               result
             )
    end

    # Test custom endpoint behavior with various scenarios
    test "uses custom endpoint", %{bypass: bypass, bypass_url: bypass_url} do
      base_llm_options = %{
        endpoint: bypass_url,
        api_key: "test-key",
        provider: :openai,
        model: "gpt-3.5-turbo"
      }

      config = %{
        name: :test_custom_endpoint_behavior,
        llm_options: base_llm_options
      }

      {:ok, agent} = Adk.create_agent(:langchain, config)

      # Test successful response from custom endpoint
      expected_response = "Response from custom endpoint"

      BypassHelper.expect_langchain_request(
        bypass,
        "POST",
        "/v1/chat/completions",
        expected_response
      )

      {:ok, result} = Adk.run(agent, "Test input")
      assert result.output.status == :completed
      assert result.output.output == expected_response

      # Test error response from custom endpoint
      error_response = %{"error" => %{"message" => "Custom endpoint error"}}

      BypassHelper.expect_langchain_error(
        bypass,
        "POST",
        "/v1/chat/completions",
        400,
        error_response
      )

      assert {:error, {:llm_provider_error, %LangChain.LangChainError{message: msg}}} =
               Adk.run(agent, "Test input")

      assert msg =~ "Custom endpoint error"

      # Test connection refused
      Bypass.down(bypass)
      assert {:error, {:llm_provider_error, error_msg}} = Adk.run(agent, "Test input")
      assert error_msg =~ "econnrefused"
    end

    test "handles invalid API key", %{bypass: bypass, bypass_url: bypass_url} do
      error_response = %{"error" => %{"message" => "Invalid API key"}}

      BypassHelper.expect_langchain_error(
        bypass,
        "POST",
        "/v1/chat/completions",
        401,
        error_response
      )

      config = %{
        name: "test_agent_invalid_key_run",
        llm_options: %{
          endpoint: bypass_url,
          api_key: "invalid_key",
          provider: :openai,
          model: "gpt-3.5-turbo"
        }
      }

      {:ok, agent} = Adk.create_agent(:langchain, config)

      assert {:error, {:llm_provider_error, %LangChain.LangChainError{message: error_message}}} =
               Adk.run(agent, "Hello")

      assert error_message =~ "Invalid API key"
    end

    # Test output schema validation with API integration
    test "API integration validates output against output schema", %{
      bypass: bypass,
      bypass_url: bypass_url
    } do
      base_llm_options = %{
        endpoint: bypass_url,
        api_key: "test-key",
        provider: :openai,
        model: "gpt-3.5-turbo"
      }

      config = %{
        name: :test_schema_output_validation_api_block,
        llm_options: base_llm_options,
        output_schema: Adk.Test.Schemas.OutputSchema
      }

      {:ok, agent} = Adk.create_agent(:langchain, config)

      # Test valid output
      valid_output_json = ~s({"answer": "It is sunny.", "confidence": 0.8})

      BypassHelper.expect_langchain_request(
        bypass,
        "POST",
        "/v1/chat/completions",
        valid_output_json
      )

      {:ok, result} = Adk.run(agent, "What's the weather?")
      assert result.output.status == :schema_validated

      assert result.output.output == %Adk.Test.Schemas.OutputSchema{
               answer: "It is sunny.",
               confidence: 0.8
             }

      # Test invalid output (missing required field)
      invalid_output_json = ~s({"answer": "It is sunny."})

      BypassHelper.expect_langchain_request(
        bypass,
        "POST",
        "/v1/chat/completions",
        invalid_output_json
      )

      assert {:error, {:schema_validation_failed, :output, _, Adk.Test.Schemas.OutputSchema}} =
               Adk.run(agent, "What's the weather?")

      # Test invalid JSON output
      invalid_json = "Not a JSON string"

      BypassHelper.expect_langchain_request(
        bypass,
        "POST",
        "/v1/chat/completions",
        invalid_json
      )

      assert {:error, {:invalid_json_output, _}} = Adk.run(agent, "What's the weather?")
    end

    # Test successful API integration with input processing
    test "API integration processes input with LangChain successfully", %{
      bypass: bypass,
      bypass_url: bypass_url
    } do
      base_llm_options = %{
        endpoint: bypass_url,
        api_key: "test-key",
        provider: :openai,
        model: "gpt-3.5-turbo"
      }

      config = %{
        name: :test_langchain_input_processing,
        llm_options: base_llm_options,
        input_schema: Adk.Test.Schemas.InputSchema
      }

      {:ok, agent} = Adk.create_agent(:langchain, config)

      # Test with valid input
      valid_input = JSON.encode!(%{query: "What's the weather?", user_id: 123})
      expected_response = "It is sunny today"

      BypassHelper.expect_langchain_request(
        bypass,
        "POST",
        "/v1/chat/completions",
        expected_response
      )

      {:ok, result} = Adk.run(agent, valid_input)
      assert result.output.status == :completed
      assert result.output.output == expected_response

      # Test with invalid input (missing required query field)
      invalid_input = JSON.encode!(%{user_id: 456})

      assert {:error, {:schema_validation_failed, :input, _, Adk.Test.Schemas.InputSchema}} =
               Adk.run(agent, invalid_input)

      # Test with non-JSON input
      assert {:error, {:invalid_json_input, "not json"}} = Adk.run(agent, "not json")
    end
  end

  # describe "Tool Handling" do ... end # Future tests
end
