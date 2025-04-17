defmodule Adk.JsonProcessor do
  @moduledoc """
  Processes LLM responses to extract and validate JSON data.

  This module provides utilities for:
  - Extracting JSON from raw LLM text outputs
  - Validating JSON against expected schemas
  - Handling errors in a way that's useful for debugging

  Note: Streaming and chunked JSON processing are not currently supported, but the API is structured to allow future extension if required by Adk workflows.
  """

  require Logger

  @doc """
  Encodes an Elixir term to a JSON string using the built-in JSON module.
  Returns {:ok, json} or {:error, reason}.
  """
  def encode(term) do
    try do
      {:ok, JSON.encode!(term)}
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Decodes a JSON string to an Elixir term using the built-in JSON module.
  Returns {:ok, term} or {:error, reason}.
  """
  def decode(json) do
    JSON.decode(json)
  end

  @doc """
  Extracts and processes JSON from an LLM response.

  ## Parameters
    * `text` - The raw text response from the LLM
    * `schema_module` - Optional module that defines the expected structure
    * `extract_regex` - Optional regex to extract JSON if it's embedded in other text

  ## Returns
    * `{:ok, decoded}` - Successfully decoded JSON (as map or struct if schema provided)
    * `{:error, reason}` - Error with descriptive reason

  ## Examples
      iex> Adk.JsonProcessor.process_json("{\"response\": \"Hello\"}")
      {:ok, %{"response" => "Hello"}}

      iex> Adk.JsonProcessor.process_json("{\"response\": \"Hello\"}", MyApp.ResponseSchema)
      {:ok, %MyApp.ResponseSchema{response: "Hello"}}
  """
  def process_json(text, schema_module \\ nil, extract_regex \\ nil) do
    json_text = extract_json(text, extract_regex)

    case decode(json_text) do
      {:ok, decoded_map} ->
        if is_nil(schema_module) do
          {:ok, decoded_map}
        else
          validate_against_schema(decoded_map, schema_module)
        end

      {:error, reason} ->
        Logger.error("JSON decode error: #{inspect(reason)}\nText: #{text}")
        {:error, {:invalid_json, text}}
    end
  end

  @doc """
  Helper function to validate if a response format looks like it might be JSON.

  ## Parameters
    * `text` - The text to check

  ## Returns
    * `true` - If the text likely contains JSON
    * `false` - Otherwise
  """
  def looks_like_json?(text) when is_binary(text) do
    text = String.trim(text)

    (String.starts_with?(text, "{") and String.ends_with?(text, "}")) or
      (String.starts_with?(text, "[") and String.ends_with?(text, "]"))
  end

  def looks_like_json?(_), do: false

  # Helper to extract JSON from text, possibly using a regex
  defp extract_json(text, nil) do
    String.trim(text)
  end

  defp extract_json(text, regex) when is_struct(regex, Regex) do
    case Regex.run(regex, text) do
      [_, json] -> String.trim(json)
      _ -> String.trim(text)
    end
  end

  # Helper to validate a decoded map against a schema
  defp validate_against_schema(decoded_map, schema_module) do
    atom_map =
      for {key, val} <- decoded_map, into: %{} do
        atom_key =
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> key
          end

        {atom_key, val}
      end

    try do
      struct = struct!(schema_module, atom_map)
      {:ok, struct}
    rescue
      error in [KeyError, ArgumentError] ->
        Logger.error("Schema validation error: #{inspect(error)}\nData: #{inspect(decoded_map)}")
        {:error, {:schema_validation_failed, schema_module, decoded_map}}
    end
  end

  @doc """
  A wrapper that can be used with Adk.Agent to post-process LLM responses.

  This function can be registered as a post-processor or message handler.

  ## Parameters
    * `response` - The raw response from the LLM
    * `schema_module` - The schema to validate against
    * `extract_regex` - Optional regex to extract JSON

  ## Returns
    * `{:ok, processed}` - Successfully processed JSON
    * `{:error, reason}` - Error with reason
  """
  def process_agent_response(response, schema_module, extract_regex \\ nil) do
    case process_json(response, schema_module, extract_regex) do
      {:ok, processed} -> {:ok, processed}
      {:error, reason} -> {:error, reason}
    end
  end
end
