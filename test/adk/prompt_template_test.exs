defmodule Adk.PromptTemplateTest do
  use ExUnit.Case

  alias Adk.PromptTemplate

  # Sample schema for testing
  defmodule TestSchema do
    @enforce_keys [:response]
    defstruct [:response, :details, is_complete: false, items: []]
  end

  describe "format/2" do
    test "is a passthrough and returns the template unchanged" do
      template = "Hello, <%= @name %>!"
      vars = %{name: "World"}
      assert PromptTemplate.format(template, vars) == template
    end
  end

  describe "with_json_output/3" do
    test "adds JSON formatting instructions to a base prompt" do
      base_prompt = "You are a helpful assistant."
      formatted_prompt = PromptTemplate.with_json_output(base_prompt, TestSchema)

      # Check that original prompt is preserved
      assert String.contains?(formatted_prompt, base_prompt)

      # Check that JSON format instructions are added
      assert String.contains?(formatted_prompt, "RESPONSE FORMAT")

      assert String.contains?(
               formatted_prompt,
               "You MUST format your response as a valid JSON object"
             )

      assert String.contains?(
               formatted_prompt,
               "Required fields: items, response, details, is_complete"
             )

      # Check that example includes default values for fields
      assert String.contains?(formatted_prompt, "\"response\":")
      assert String.contains?(formatted_prompt, "\"is_complete\": false")
      assert String.contains?(formatted_prompt, "\"items\": []")
    end

    test "includes custom example if provided" do
      base_prompt = "You are a helpful assistant."

      custom_example = """
      {
        "response": "This is a sample response",
        "details": "Extra information",
        "is_complete": true,
        "items": ["item1", "item2"]
      }
      """

      formatted_prompt = PromptTemplate.with_json_output(base_prompt, TestSchema, custom_example)

      # Check that our custom example is included
      assert String.contains?(formatted_prompt, "This is a sample response")
      assert String.contains?(formatted_prompt, "Extra information")
      assert String.contains?(formatted_prompt, "\"is_complete\": true")
      assert String.contains?(formatted_prompt, "item1")
      assert String.contains?(formatted_prompt, "item2")
    end
  end
end
