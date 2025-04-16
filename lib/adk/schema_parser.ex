defmodule Adk.SchemaParser do
  @moduledoc """
  Handles parsing of LLM responses into Ecto schemas using Instructor.
  This module separates the schema parsing logic from the LLM interaction.
  """

  @doc """
  Parses an LLM response into a structured Ecto schema.

  ## Parameters
    * `content` - The raw content from the LLM response
    * `schema_module` - The Ecto schema module to parse into (must use Instructor.Validator)

  ## Returns
    * `{:ok, parsed}` - Successfully parsed content into the schema
    * `{:error, reason}` - Failed to parse the content
  """
  def parse_llm_response(content, schema_module) when is_binary(content) do
    # Use Instructor's parsing capabilities without the chat completion
    case JSON.decode(content) do
      {:ok, decoded} ->
        # Apply the schema's changeset validation
        schema_module
        |> struct()
        |> schema_module.changeset(decoded)
        |> validate_and_load(schema_module)

      {:error, _} ->
        # If content isn't JSON, try to parse it as a complete JSON object
        case wrap_and_parse(content, schema_module) do
          {:ok, _} = result -> result
          {:error, _} -> {:error, "Failed to parse LLM response into schema"}
        end
    end
  end

  def parse_llm_response(content, _schema_module) do
    {:error, "Invalid content format: #{inspect(content)}"}
  end

  @doc """
  Returns the JSON schema for a given Ecto schema module.
  This can be used to instruct the LLM about the expected response format.

  ## Example

      defmodule MySchema do
        use Ecto.Schema
        use Instructor

        embedded_schema do
          field :name, :string
          field :age, :integer
        end
      end

      SchemaParser.get_json_schema(MySchema)
      # Returns a JSON schema map
  """
  def get_json_schema(schema_module) do
    schema_module.__instructor__(:json_schema)
  end

  # Private helpers

  defp validate_and_load(changeset, schema_module) do
    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, struct} ->
        {:ok, struct}

      {:error, changeset} ->
        # Try running the schema's custom validation if it exists
        if function_exported?(schema_module, :validate_response, 1) do
          changeset
          |> schema_module.validate_response()
          |> Ecto.Changeset.apply_action(:insert)
        else
          {:error, changeset}
        end
    end
  end

  defp wrap_and_parse(content, schema_module) do
    # Try to extract structured data from unstructured content
    # This is a simple example - you might want to make this more sophisticated
    try do
      _fields = schema_module.__schema__(:fields)

      # Create a map matching the schema's fields from the content
      parsed = %{
        "content" => content
        # Add other fields as needed
      }

      struct(schema_module)
      |> schema_module.changeset(parsed)
      |> validate_and_load(schema_module)
    rescue
      _ -> {:error, "Could not parse unstructured content"}
    end
  end
end
