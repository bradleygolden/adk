defmodule Adk.PromptTemplate do
  @moduledoc """
  Provides utilities for working with prompt templates.

  This module allows creating, formatting, and composing prompts with support for
  structured output requirements like JSON formatting. It also supports rendering
  EEx-style prompt templates with variables from maps or structs using LangChain.
  """

  @doc """
  Renders a prompt template string with the given map or struct as variables.

  Uses LangChain's EEx-based prompt templating under the hood.

  ## Examples
      iex> Adk.PromptTemplate.render("Hello, <%= @name %>!", %{name: "World"})
      "Hello, World!"

      iex> defmodule User do
      ...>   defstruct [:name]
      ...> end
      iex> Adk.PromptTemplate.render("Hi, <%= @name %>!", %User{name: "Alice"})
      "Hi, Alice!"
  """
  @spec render(String.t(), map() | struct()) :: String.t()
  def render(template, vars) when is_binary(template) and (is_map(vars) or is_struct(vars)) do
    LangChain.PromptTemplate.format_text(template, vars)
  end

  @doc """
  Creates a new prompt that requires JSON output format.

  ## Parameters
    * `base_prompt` - The original prompt content
    * `schema` - A module that defines the expected JSON structure
    * `example` - Optional example of the expected output format

  ## Returns
    A formatted prompt string with JSON output requirement instructions

  ## Examples
      iex> base_prompt = "You are a helpful assistant."
      iex> Adk.PromptTemplate.with_json_output(base_prompt, MyApp.OutputSchema)
  """
  def with_json_output(base_prompt, schema, example \\ nil) when is_binary(base_prompt) do
    required_fields =
      schema.__struct__()
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.map(&to_string/1)

    # If the schema provides field descriptions, format them for the prompt
    field_descriptions =
      if function_exported?(schema, :field_descriptions, 0) do
        schema.field_descriptions()
      else
        %{}
      end

    description_section =
      if map_size(field_descriptions) > 0 do
        descs =
          Enum.map(required_fields, fn field ->
            desc = Map.get(field_descriptions, String.to_atom(field)) || ""
            "- `#{field}`: #{desc}"
          end)
          |> Enum.join("\n")

        """
        Field Descriptions:
        #{descs}
        """
      else
        ""
      end

    json_format = """

    RESPONSE FORMAT:
    You MUST format your response as a valid JSON object with the following structure:
    #{description_section}#{build_json_schema_example(schema, example)}

    Required fields: #{if Enum.empty?(required_fields), do: "none", else: Enum.join(required_fields, ", ")}

    IMPORTANT: Your ENTIRE response must be VALID JSON. Do not include ANY text before or after the JSON object.
    """

    base_prompt <> json_format
  end

  # Helper to build an example JSON schema
  defp build_json_schema_example(schema, nil) do
    # Get all fields
    fields =
      schema.__struct__()
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.map(&{&1, get_default_value_for_field(&1)})
      |> Enum.into(%{})

    # Convert to pretty JSON
    Jason.encode!(fields, pretty: true)
  end

  defp build_json_schema_example(_schema, example) when is_binary(example) do
    example
  end

  defp build_json_schema_example(_schema, example) when is_map(example) do
    Jason.encode!(example, pretty: true)
  end

  # Provide sensible default values based on field name patterns
  defp get_default_value_for_field(field) do
    field_name = to_string(field)

    cond do
      String.ends_with?(field_name, "_list") ||
          (String.ends_with?(field_name, "s") && not String.ends_with?(field_name, "ss")) ->
        []

      String.starts_with?(field_name, "is_") ||
        String.starts_with?(field_name, "has_") ||
          String.ends_with?(field_name, "?") ->
        false

      String.ends_with?(field_name, "_count") ||
          String.ends_with?(field_name, "_number") ->
        0

      true ->
        nil
    end
  end
end
