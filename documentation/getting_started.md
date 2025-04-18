# Getting Started with ADK

## Prerequisites

- Elixir 1.14 or newer
- Erlang/OTP 25 or newer

## Installation

Add `adk` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:adk, "~> 0.1.0"},
    # Optional: add LangChain support (version 0.3.2 or newer recommended)
    {:langchain, "~> 0.3.2", optional: true}
  ]
end
```

Fetch dependencies:

```sh
mix deps.get
```

## First Agent: Hello World

Create and run a simple sequential agent:

```elixir
{:ok, agent} = Adk.create_agent(:sequential, %{
  name: "hello_agent",
  steps: [
    %{type: "function", function: fn _ -> "Hello, ADK!" end}
  ]
})
{:ok, result} = Adk.run(agent, nil)
IO.puts(result.output) # => "Hello, ADK!"
```

## Creating a Tool

Define a custom tool by implementing the `Adk.Tool` behavior:

```elixir
defmodule MyTool do
  use Adk.Tool
  
  @impl true
  def definition do
    %{
      name: "my_tool",
      description: "A tool that performs some action",
      parameters: %{
        input: %{
          type: "string",
          description: "The input to process"
        }
      }
    }
  end
  
  @impl Adk.Tool
  def execute(%{"input" => input}, _context) do
    {:ok, "Processed: #{input}"}
  end
end

# Register the tool
Adk.register_tool(MyTool)
```

## Using a Tool in an Agent

```elixir
{:ok, agent} = Adk.create_agent(:sequential, %{
  name: "tool_using_agent",
  steps: [
    %{type: "tool", tool: "my_tool", params: %{"input" => "test data"}}
  ]
})
{:ok, result} = Adk.run(agent, nil)
IO.puts(result.output) # => "Processed: test data"
```

## Optional: LLM Integration

If you want to use LLM-powered agents, add `:langchain` to your dependencies. ADK will detect and use it automatically for `:langchain` agent types.

## Next Steps

- Explore [Agent Types](guides/agent_types.md)
- Learn about [Tools](guides/tools.md)
- See [Memory](guides/memory.md)
- Try the examples in the `examples/` directory 