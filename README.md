# Adk - Agent Development Kit for Elixir

A powerful framework for building, running, and managing intelligent agents in Elixir, implementing the core architecture of Google's Agent Development Kit (Adk) with idiomatic Elixir and OTP.

## Installation

Add `adk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:adk, "~> 0.1.0"},
    # Optional: add LangChain support (version 0.3.2 or newer recommended)
    {:langchain, "~> 0.3.2", optional: true}
  ]
end
```

The LangChain integration is completely optional. If present, Adk will automatically detect and use it, providing additional agent capabilities through the `:langchain` agent type.

## QuickStart

```elixir
{:ok, agent} = Adk.create_agent(:sequential, %{
  name: "hello_agent",
  steps: [%{type: "function", function: fn _ -> "Hello, ADK!" end}]
})
{:ok, result} = Adk.run(agent, nil)
IO.puts(result.output)
```

## Core Concepts

- **Agent**: Orchestrate logic through different agent types:
  - **Sequential**: Execute steps in order, passing output to the next step
  - **Parallel**: Run multiple tasks concurrently and combine results
  - **Loop**: Repeat steps until a condition is met
  - **LLM**: Use language models for reasoning and tool selection
- **Tools**: Define external actions via `use Adk.Tool` and register with `Adk.register_tool/1`
- **Memory**: Persist session history and state via `Adk.Memory`
- **Event System**: Track agent activities for debugging and auditing

## Testing Agents

Adk includes a built-in ExUnit harness to make agent tests concise, deterministic, and fast.

### Using the Test Framework

The test harness is included in the core library, so you can start using it right away:

```elixir
defmodule MyAgentTest do
  use ExUnit.Case, async: true
  use Adk.Test.AgentCase

  test "agent produces expected output" do
    stub_llm("Test response")
    
    agent = create_test_agent(:sequential, %{
      name: "test_agent",
      steps: [%{type: "function", function: fn _ -> "Hello, world!" end}]
    })
    
    assert_agent_output(agent, nil, "Hello, world!")
  end
end
```

### Available Test Helpers

The `Adk.Test.Helpers` module provides several key functions:

- `assert_agent_output/3`: Verify an agent produces expected output
- `stub_llm/1`: Stub LLM responses for deterministic testing
- `capture_events/1`: Capture events emitted during agent execution
- `create_test_agent/2`: Convenience wrapper for agent creation

### Sample Test

Here's an example of testing an LLM agent with stubbed responses:

```elixir
test "llm agent with stubbed response" do
  stub_llm("The answer is 42")
  
  agent = create_test_agent(:llm, %{
    name: "answer_agent",
    prompt: "What is the answer to life, the universe, and everything?"
  })
  
  assert_agent_output(agent, nil, "The answer is 42")
end
```

## Evaluating Agents

Adk includes a programmatic evaluation system inspired by the Google Agent Development Kit's evaluation workflow. This allows for data-driven, automated testing of agent behaviors using JSON evaluation files.

### JSON-Based Evaluation

You can define test scenarios in JSON format:
- `.test.json` - For individual test cases
- `.evalset.json` - For multiple evaluation sessions

Example test file (`examples/sample_evaluation.test.json`):
```json
[
  {
    "query": "Hi there",
    "expected_tool_use": [],
    "expected_intermediate_agent_responses": [],
    "reference": "Hello! How can I help you today?"
  },
  {
    "query": "What's 25 * 16?",
    "expected_tool_use": [
      {
        "tool_name": "calculator",
        "tool_input": {
          "operation": "multiply",
          "operands": [25, 16]
        }
      }
    ],
    "expected_intermediate_agent_responses": [],
    "reference": "25 * 16 = 400"
  }
]
```

### Using the Evaluator in ExUnit

The evaluator can be integrated with ExUnit tests for automated evaluation:

```elixir
defmodule MyAgentEvaluationTest do
  use ExUnit.Case, async: true
  
  test "agent passes all evaluation scenarios" do
    results = Adk.Evaluator.evaluate(
      MyAgent,
      "test/fixtures/my_agent_eval.test.json"
    )
    
    assert results.all_passed?
  end
end
```

### Evaluation Metrics

The evaluator computes two key metrics:
- `tool_trajectory_avg_score`: How accurately the agent used the expected tools
- `response_match_score`: How closely the agent's final response matches the reference

You can specify custom thresholds in a `test_config.json` file:
```json
{
  "criteria": {
    "tool_trajectory_avg_score": 1.0,
    "response_match_score": 0.8
  }
}
```

## Guides & API Reference

- [Getting Started](documentation/getting_started.md)
- [Agent Types](documentation/guides/agent_types.md)
- [Tools](documentation/guides/tools.md)
- [Memory](documentation/guides/memory.md)
- [Overview](documentation/guides/overview.md)
- [Telemetry](documentation/telemetry.md)
- [API Reference](https://hexdocs.pm/adk)

## Architectural Design

```

## Contributing

Contributions are welcome! Here are some ways to help:

1. Implement additional agent types
2. Create new tools for specialized domains
3. Build memory backends for external databases
4. Improve LLM provider implementations and testing
5. Improve documentation and examples
6. Report bugs and suggest features

## License

MIT License