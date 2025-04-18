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

## Examples Gallery

See the `examples/` directory for working examples, including:
- Calculator Agent (examples/calculator_agent_example.livemd)

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

## Guides & API Reference

- [Getting Started](docs/getting_started.md)
- [Agent Types](docs/guides/agent_types.md)
- [Tools](docs/guides/tools.md)
- [Memory](docs/guides/memory.md)
- [Overview](docs/guides/overview.md)
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