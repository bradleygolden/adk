defmodule Adk.PromptTemplateTest do
  use ExUnit.Case

  alias Adk.PromptTemplate

  defmodule User do
    defstruct [:name, :color]
  end

  # Sample schema for testing
  defmodule TestSchema do
    @enforce_keys [:response]
    defstruct [:response, :details, is_complete: false, items: []]
  end

  defmodule DescribedSchema do
    @enforce_keys [:foo, :bar]
    defstruct [:foo, :bar]
    @field_descriptions %{foo: "Foo field description.", bar: "Bar field description."}
    def field_descriptions, do: @field_descriptions
  end

  describe "render/2" do
    test "renders template with map variables" do
      template = "Hello, <%= @name %>! Your favorite color is <%= @color %>."
      vars = %{name: "Alice", color: "blue"}
      assert PromptTemplate.render(template, vars) == "Hello, Alice! Your favorite color is blue."
    end

    test "renders template with struct variables" do
      template = "Hi, <%= @name %>! Your favorite color is <%= @color %>."
      user = %User{name: "Bob", color: "green"}
      assert PromptTemplate.render(template, user) == "Hi, Bob! Your favorite color is green."
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

    test "includes field descriptions if provided by schema" do
      base_prompt = "You are a helpful assistant."
      formatted_prompt = PromptTemplate.with_json_output(base_prompt, DescribedSchema)
      assert String.contains?(formatted_prompt, "Field Descriptions:")
      assert String.contains?(formatted_prompt, "- `foo`: Foo field description.")
      assert String.contains?(formatted_prompt, "- `bar`: Bar field description.")
    end
  end
end
