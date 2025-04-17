defmodule Adk.PromptTemplate do
  @moduledoc """
  Provides utilities for working with prompt templates.

  This module allows creating, formatting, and composing prompts with support for
  structured output requirements like JSON formatting.
  """

  @doc """
  (DEPRECATED) Formats a prompt with variables using EEx templating.

  This is no longer necessary. Pass your template and variables directly to LangChain's prompt builder or chat API.
  This function is now a passthrough and will be removed in a future version.
  """
  def format(template, _vars \\ %{}) when is_binary(template), do: template

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
    # Treat all struct fields as required
    required_fields =
      schema.__struct__()
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.map(&to_string/1)

    # Build the JSON format description
    json_format = """

    RESPONSE FORMAT:
    You MUST format your response as a valid JSON object with the following structure:
    #{build_json_schema_example(schema, example)}

    Required fields: #{if Enum.empty?(required_fields), do: "none", else: Enum.join(required_fields, ", ")}

    IMPORTANT: Your ENTIRE response must be VALID JSON. Do not include ANY text before or after the JSON object.
    """

    # Return the combined prompt
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
