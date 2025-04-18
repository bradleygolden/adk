# Tools in ADK

Tools are the primary way for agents to interact with the outside world or perform specialized actions. This guide explains how to define, register, and use tools in ADK.

## What is a Tool?

A tool is a module that implements the `Adk.Tool` behaviour. Tools can perform computations, call APIs, access memory, or provide any custom logic that agents can invoke as part of their workflow.

## Anatomy of a Tool Module

To define a tool, create a module and `use Adk.Tool`. Implement the required callbacks:

- `definition/0`: Returns a map describing the tool (name, description, parameters, etc.)
- `execute/2`: Executes the tool logic. Receives parameters and a context map.

## Example: Test Tool

```elixir
defmodule TestTool do
  use Adk.Tool

  @impl true
  def definition do
    %{
      name: "test_tool",
      description: "A test tool for testing",
      parameters: %{
        input: %{
          type: "string",
          description: "The input to the tool"
        }
      }
    }
  end

  @impl Adk.Tool
  def execute(%{"input" => input}, _context) do
    {:ok, "Processed: #{input}"}
  end
end
```

## Registering a Tool

Register your tool so agents can use it:

```elixir
Adk.register_tool(TestTool)
```

Alternatively, you can register with a specific name:

```elixir
Adk.ToolRegistry.register(:test_tool, TestTool)
```

## Using Tools in Agents

### In Sequential Agents

```elixir
{:ok, agent} = Adk.create_agent(:sequential, %{
  name: "tool_agent",
  steps: [
    %{type: "tool", tool: "test_tool", params: %{"input" => "example"}}
  ]
})
{:ok, result} = Adk.run(agent, nil)
IO.puts(result.output) # => "Processed: example"
```

### In Parallel Agents

```elixir
{:ok, agent} = Adk.create_agent(:parallel, %{
  name: "parallel_tool_agent",
  tasks: [
    %{type: "tool", tool: "test_tool", params: %{"input" => "task1"}},
    %{type: "tool", tool: "test_tool", params: %{"input" => "task2"}}
  ]
})
{:ok, result} = Adk.run(agent, nil)
```

### In LLM Agents

LLM agents can dynamically choose to use tools. You need to provide the tools in the agent configuration:

```elixir
{:ok, agent} = Adk.create_agent(:llm, %{
  name: "llm_with_tools",
  llm_provider: MyLLMProvider,
  tools: [TestTool.definition()]
})
{:ok, result} = Adk.run(agent, "Can you process something for me?")
```

## Tool Registry

The `Adk.ToolRegistry` manages tool registration:

```elixir
# Register a tool
Adk.ToolRegistry.register(:tool_name, ToolModule)

# List all registered tools
tools = Adk.ToolRegistry.list()

# Look up a tool by name
{:ok, tool_module} = Adk.ToolRegistry.lookup(:tool_name)
```

## Best Practices

- Keep tool logic focused and stateless when possible.
- Use the `context` argument for session or invocation-specific data.
- Return `{:ok, result}` or `{:error, reason}` from `execute/2`.
- Document parameters clearly in the `definition/0` map.
- Register tools at application startup for global availability.

## Error Handling

Tools should handle errors gracefully and return `{:error, reason}` tuples. Sequential agents will stop execution on errors, while parallel agents can be configured to continue or halt on errors with the `halt_on_error` option.

For more examples, see the `examples/` directory. 