defmodule Adk.Evaluator do
  @moduledoc """
  Programmatic evaluation system for Adk agents.

  Provides functions to load and run evaluation scenarios from JSON files and compute metrics.
  Following the Agent Development Kit (ADK) evaluation approach, this allows for automated,
  reproducible testing of agent behavior using test files and evalsets.
  """

  alias Adk.Evaluator.JsonLoader
  alias Adk.Test.Helpers

  @doc """
  Evaluates an agent against a test dataset.

  ## Parameters

  - `agent_module`: The agent module to evaluate (atom or string), an agent struct, or a PID of a running agent server
  - `eval_dataset`: Path to the evaluation dataset file (.test.json or .evalset.json)
  - `opts`: Additional options
    - `:initial_session_file` - Path to a session state file (JSON) to use as initial state
    - `:config_file_path` - Path to a configuration file with custom evaluation criteria

  ## Returns

  A map with evaluation results:

  ```
  %{
    all_passed?: true/false,
    total_scenarios: 3,
    passed_scenarios: 3,
    metrics: %{
      tool_trajectory_avg_score: 0.91,
      response_match_score: 0.85
    },
    scenario_results: [...]
  }
  ```
  """
  @spec evaluate(module() | struct() | pid() | String.t(), String.t(), keyword()) :: map()
  def evaluate(agent, eval_dataset, opts \\ []) do
    # Load the agent module if it's a string
    agent =
      if is_binary(agent) do
        String.to_existing_atom(agent)
      else
        agent
      end

    # Load the evaluation dataset
    scenarios = JsonLoader.load_eval_dataset(eval_dataset)

    # Load config if provided
    config =
      case Keyword.get(opts, :config_file_path) do
        nil -> default_config()
        path -> JsonLoader.load_config(path)
      end

    # Load initial session state if provided - we're not using this yet
    # but keeping the code for future extension
    _initial_session =
      case Keyword.get(opts, :initial_session_file) do
        nil -> nil
        path -> JsonLoader.load_session(path)
      end

    # Run the evaluation
    run_evaluation(agent, scenarios, config)
  end

  @doc """
  Returns the default evaluation configuration.
  """
  def default_config do
    %{
      criteria: %{
        tool_trajectory_avg_score: 1.0,
        response_match_score: 0.8
      }
    }
  end

  # Runs all evaluation scenarios and collects results
  defp run_evaluation(agent, scenarios, config) do
    # No need to create an agent if we already have one (PID or struct)
    agent_for_eval = agent

    # Run each scenario and collect results
    scenario_results =
      Enum.map(scenarios, fn scenario ->
        evaluate_scenario(agent_for_eval, scenario, config)
      end)

    # Compute aggregate metrics
    passed_scenarios = Enum.count(scenario_results, & &1.passed?)
    tool_scores = Enum.map(scenario_results, & &1.metrics.tool_trajectory_score)
    response_scores = Enum.map(scenario_results, & &1.metrics.response_match_score)

    %{
      all_passed?: passed_scenarios == length(scenarios),
      total_scenarios: length(scenarios),
      passed_scenarios: passed_scenarios,
      metrics: %{
        tool_trajectory_avg_score: avg(tool_scores),
        response_match_score: avg(response_scores)
      },
      scenario_results: scenario_results
    }
  end

  # Evaluates a single scenario
  defp evaluate_scenario(agent, scenario, config) do
    # Get the expected values
    %{
      "query" => query,
      "expected_tool_use" => expected_tool_use,
      "expected_intermediate_agent_responses" => _expected_intermediate_responses,
      "reference" => expected_output
    } = scenario

    # Set up event capture to monitor tool usage
    {result, events} =
      Helpers.capture_events(fn ->
        Adk.run(agent, query)
      end)

    # Extract the actual output
    actual_output =
      case result do
        {:ok, %{output: output}} -> output
        _ -> ""
      end

    # Extract tool usage events
    tool_events =
      Enum.filter(events, fn event ->
        event.type == :tool_called
      end)

    actual_tool_use =
      Enum.map(tool_events, fn event ->
        %{
          "tool_name" => event.data.tool_name,
          "tool_input" => event.data.params
        }
      end)

    # Compute metrics
    tool_trajectory_score = calculate_tool_trajectory_score(actual_tool_use, expected_tool_use)
    response_match_score = calculate_response_match_score(actual_output, expected_output)

    # Determine if the scenario passed based on the config criteria
    passed? =
      tool_trajectory_score >= config.criteria.tool_trajectory_avg_score and
        response_match_score >= config.criteria.response_match_score

    # Return scenario result
    %{
      query: query,
      expected_output: expected_output,
      actual_output: actual_output,
      expected_tool_use: expected_tool_use,
      actual_tool_use: actual_tool_use,
      passed?: passed?,
      metrics: %{
        tool_trajectory_score: tool_trajectory_score,
        response_match_score: response_match_score
      }
    }
  end

  # Calculates the tool trajectory score based on exact matches
  defp calculate_tool_trajectory_score(actual_tools, expected_tools) do
    cond do
      # If no tools expected and none used, perfect score
      Enum.empty?(expected_tools) and Enum.empty?(actual_tools) ->
        1.0

      # If tools expected but none used, or vice versa, zero score
      Enum.empty?(expected_tools) or Enum.empty?(actual_tools) ->
        0.0

      # Otherwise, calculate the match score
      true ->
        # Exact match for now - we can implement more sophisticated matching later
        if actual_tools == expected_tools do
          1.0
        else
          # Count the number of matches
          matches = min(length(actual_tools), length(expected_tools))
          matches / max(length(actual_tools), length(expected_tools))
        end
    end
  end

  # Calculates response match score
  # In a real implementation, you might want to use a more sophisticated metric like ROUGE
  defp calculate_response_match_score(actual, expected) do
    if actual == expected do
      1.0
    else
      # Simple string similarity for now
      # In a real implementation, consider using a library for this
      actual_words = String.split(actual, ~r/\s+/) |> MapSet.new()
      expected_words = String.split(expected, ~r/\s+/) |> MapSet.new()

      intersection = MapSet.intersection(actual_words, expected_words) |> MapSet.size()
      union = MapSet.union(actual_words, expected_words) |> MapSet.size()

      if union == 0, do: 0.0, else: intersection / union
    end
  end

  # Helper to calculate average
  defp avg([]), do: 0.0
  defp avg(list), do: Enum.sum(list) / length(list)
end
