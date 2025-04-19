defmodule Adk.Evaluator.JsonLoader do
  @moduledoc """
  Module for loading and validating JSON evaluation files.

  Supports loading both .test.json and .evalset.json files, as well as configuration
  files and initial session state.
  """

  @doc """
  Loads and validates an evaluation dataset from a JSON file.

  Supports both test files (.test.json) and evalset files (.evalset.json).

  ## Parameters

  - `path`: Path to the JSON file

  ## Returns

  A list of scenarios, where each scenario is a map with the keys:
  - `query`: The query to send to the agent
  - `expected_tool_use`: List of expected tool calls
  - `expected_intermediate_agent_responses`: List of expected intermediate responses
  - `reference`: The expected final response
  """
  @spec load_eval_dataset(String.t()) :: list(map())
  def load_eval_dataset(path) do
    # Read and parse the JSON file
    json = read_json_file(path)

    # Determine the file type from the extension
    file_type =
      if String.ends_with?(path, ".test.json"),
        do: :test,
        else:
          if(String.ends_with?(path, ".evalset.json"),
            do: :evalset,
            else:
              raise("Unsupported file extension: #{path}. Expected .test.json or .evalset.json")
          )

    # Parse according to the file type
    case file_type do
      :test -> parse_test_file(json)
      :evalset -> parse_evalset_file(json)
    end
  end

  @doc """
  Loads and validates a configuration file from JSON.

  ## Parameters

  - `path`: Path to the JSON file

  ## Returns

  A configuration map with the keys:
  - `criteria`: Map of criteria with threshold values
  """
  @spec load_config(String.t()) :: map()
  def load_config(path) do
    # Read and parse the JSON file
    json = read_json_file(path)

    # Validate the config
    validate_config(json)
  end

  @doc """
  Loads an initial session state from JSON.

  ## Parameters

  - `path`: Path to the JSON file

  ## Returns

  A session state map
  """
  @spec load_session(String.t()) :: map()
  def load_session(path) do
    # Read and parse the JSON file
    read_json_file(path)
  end

  # Private functions

  # Reads and parses a JSON file
  defp read_json_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, json} -> json
          {:error, _} -> raise "Invalid JSON in file: #{path}"
        end

      {:error, _} ->
        raise "Could not read file: #{path}"
    end
  end

  # Parses a test file (list of scenarios)
  defp parse_test_file(json) when is_list(json) do
    Enum.map(json, &validate_scenario/1)
  end

  defp parse_test_file(_), do: raise("Invalid test file: expected an array of scenarios")

  # Parses an evalset file (list of eval groups, each with scenarios)
  defp parse_evalset_file(json) when is_list(json) do
    # Flatten all scenarios from all evalsets
    json
    |> Enum.flat_map(fn eval_group ->
      name = Map.get(eval_group, "name", "unnamed")
      data = Map.get(eval_group, "data", [])

      # Validate each scenario in the group
      data
      |> Enum.map(&validate_scenario/1)
      |> Enum.map(fn scenario ->
        # Add the evalset name to each scenario for better reporting
        Map.put(scenario, "evalset_name", name)
      end)
    end)
  end

  defp parse_evalset_file(_), do: raise("Invalid evalset file: expected an array of eval groups")

  # Validates a scenario and returns it
  defp validate_scenario(scenario) when is_map(scenario) do
    # Check required keys
    required_keys = ["query", "expected_tool_use", "reference"]
    missing_keys = Enum.filter(required_keys, &(!Map.has_key?(scenario, &1)))

    unless Enum.empty?(missing_keys) do
      raise "Invalid scenario: missing required keys #{inspect(missing_keys)}"
    end

    # Validate expected_tool_use is a list
    tool_use = Map.get(scenario, "expected_tool_use")

    unless is_list(tool_use) do
      raise "Invalid scenario: expected_tool_use must be an array"
    end

    # Validate tool use items
    Enum.each(tool_use, fn tool ->
      unless is_map(tool) and Map.has_key?(tool, "tool_name") do
        raise "Invalid tool use: each tool must be an object with at least a tool_name"
      end
    end)

    # Ensure expected_intermediate_agent_responses exists (default to empty list)
    scenario = Map.put_new(scenario, "expected_intermediate_agent_responses", [])

    scenario
  end

  defp validate_scenario(_), do: raise("Invalid scenario: expected an object")

  # Validates a config file
  defp validate_config(config) when is_map(config) do
    # Check for criteria key
    unless Map.has_key?(config, "criteria") do
      raise "Invalid config: missing 'criteria' key"
    end

    criteria = Map.get(config, "criteria")

    unless is_map(criteria) do
      raise "Invalid config: 'criteria' must be an object"
    end

    # Convert string keys to atoms
    %{
      criteria: %{
        tool_trajectory_avg_score: Map.get(criteria, "tool_trajectory_avg_score", 1.0),
        response_match_score: Map.get(criteria, "response_match_score", 0.8)
      }
    }
  end

  defp validate_config(_), do: raise("Invalid config: expected an object")
end
