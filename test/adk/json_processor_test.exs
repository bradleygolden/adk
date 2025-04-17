defmodule Adk.JsonProcessorTest do
  use ExUnit.Case

  alias Adk.JsonProcessor

  # Sample schema for testing
  defmodule TestSchema do
    @enforce_keys [:response]
    defstruct [:response, :details, is_complete: false, items: []]
  end

  describe "process_json/3" do
    test "processes valid JSON with no schema" do
      json =
        ~s({"response": "Hello", "details": "World", "is_complete": true, "items": [1, 2, 3]})

      assert {:ok, decoded} = JsonProcessor.process_json(json)
      assert decoded["response"] == "Hello"
      assert decoded["details"] == "World"
      assert decoded["is_complete"] == true
      assert decoded["items"] == [1, 2, 3]
    end

    test "processes valid JSON with schema validation" do
      json =
        ~s({"response": "Hello", "details": "World", "is_complete": true, "items": [1, 2, 3]})

      assert {:ok, decoded} = JsonProcessor.process_json(json, TestSchema)
      assert decoded.response == "Hello"
      assert decoded.details == "World"
      assert decoded.is_complete == true
      assert decoded.items == [1, 2, 3]
    end

    test "returns error for invalid JSON" do
      json = ~s({"response": "Hello", "details": "World", "is_complete": true, "items": [1, 2, 3)
      assert {:error, {:invalid_json, _}} = JsonProcessor.process_json(json)
    end

    test "returns error for JSON missing required fields" do
      json = ~s({"details": "World", "is_complete": true, "items": [1, 2, 3]})

      assert {:error, {:schema_validation_failed, TestSchema, _}} =
               JsonProcessor.process_json(json, TestSchema)
    end

    test "extracts JSON from text using regex" do
      text = "Here is the result: ```json{\"response\": \"Hello\"}``` Thank you!"
      regex = ~r/```json(.*?)```/s
      assert {:ok, decoded} = JsonProcessor.process_json(text, nil, regex)
      assert decoded["response"] == "Hello"
    end
  end

  describe "looks_like_json?/1" do
    test "returns true for valid JSON object format" do
      assert JsonProcessor.looks_like_json?(" { \"key\": \"value\" } ")
    end

    test "returns true for valid JSON array format" do
      assert JsonProcessor.looks_like_json?(" [ 1, 2, 3 ] ")
    end

    test "returns false for non-JSON text" do
      refute JsonProcessor.looks_like_json?("Hello world")
    end

    test "returns false for incomplete JSON" do
      refute JsonProcessor.looks_like_json?("{ \"key\": \"value\"")
    end

    test "returns false for non-string input" do
      refute JsonProcessor.looks_like_json?(nil)
      refute JsonProcessor.looks_like_json?(123)
      refute JsonProcessor.looks_like_json?([])
    end
  end

  describe "process_agent_response/3" do
    test "processes valid JSON response with schema" do
      response = ~s({"response": "Hello", "details": "World", "is_complete": true, "items": []})
      assert {:ok, processed} = JsonProcessor.process_agent_response(response, TestSchema)
      assert processed.response == "Hello"
      assert processed.details == "World"
      assert processed.is_complete == true
    end

    test "handles invalid JSON in agent response" do
      response = "Sorry, I don't understand your question."

      assert {:error, {:invalid_json, _}} =
               JsonProcessor.process_agent_response(response, TestSchema)
    end

    test "extracts and processes JSON from formatted agent response" do
      response =
        "Here's my answer:\n```json\n{\"response\": \"Hello\", \"is_complete\": false, \"items\": []}\n```"

      regex = ~r/```json\n(.*?)\n```/s
      assert {:ok, processed} = JsonProcessor.process_agent_response(response, TestSchema, regex)
      assert processed.response == "Hello"
      assert processed.is_complete == false
    end
  end
end
