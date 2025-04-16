# ADK - Agent Development Kit for Elixir

> [!WARNING]  
> This repository was almost entirely generated by Claude AI and is highly experimental. Use at your own risk.

A powerful framework for building, running, and managing intelligent agents in Elixir, implementing the core architecture of Google's Agent Development Kit (ADK) with idiomatic Elixir and OTP.

## Features

- **Agent Abstraction** - Multiple agent types for different use cases:
  - **Sequential Agents**: Execute steps in order with results flowing between steps
  - **Parallel Agents**: Run operations concurrently for high-performance tasks
  - **Loop Agents**: Repeat actions until specific conditions are met
  - **LLM Agents**: Use language models for reasoning and decision-making
  - **LangChain Agents**: Integrate with the LangChain Elixir library for enhanced capabilities
  
- **Tool System** - Plugin architecture for agents to interact with external systems:
  - Behavior-based interface for easy tool creation
  - Automatic tool registration and discovery
  - Structured parameter and response handling
  
- **Memory Services** - Persistent state across interactions:
  - Short-term memory within agent sessions
  - Long-term memory via pluggable storage backends
  - Memory search and retrieval capabilities
  
- **Agent Orchestration** - Powerful composition patterns:
  - Hierarchical agent relationships
  - Delegation to specialized sub-agents
  - Cross-agent communication
  
- **OTP Architecture** - Built on Elixir's concurrency model:
  - Process isolation for fault tolerance
  - Supervisor trees for reliability
  - GenServer-based state management
  
- **A2A Protocol** - Agent-to-Agent communication:
  - Local inter-agent messaging
  - HTTP-based remote agent interaction
  - Standardized message format

## Installation

Add `adk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:adk, "~> 0.1.0"},
    # Optional: add LangChain support
    {:langchain, "~> 0.3.2", optional: true}
  ]
end
```

## Usage Examples

### Basic Sequential Agent

```elixir
# Create a tool
defmodule MyApp.Tools.Weather do
  use Adk.Tool
  
  @impl true
  def definition do
    %{
      name: "weather",
      description: "Get the weather for a location",
      parameters: %{
        location: %{
          type: "string",
          description: "The location to get weather for"
        }
      }
    }
  end
  
  @impl true
  def execute(%{"location" => location}) do
    # In a real implementation, you would call a weather API
    {:ok, "The weather in #{location} is sunny."}
  end
end

# Register the tool
Adk.register_tool(MyApp.Tools.Weather)

# Create a sequential agent
{:ok, agent} = Adk.create_agent(:sequential, %{
  name: "weather_agent",
  steps: [
    %{
      type: "tool",
      tool: "weather",
      params: %{"location" => "London"}
    }
  ]
})

# Run the agent
{:ok, result} = Adk.run(agent, "What's the weather in London?")
IO.puts(result.output)
```

### LLM-driven Agent

```elixir
# Register tools
Adk.register_tool(MyApp.Tools.Weather)
Adk.register_tool(Adk.Tools.MemoryTool)

# Create an LLM agent
{:ok, agent} = Adk.create_agent(:llm, %{
  name: "assistant",
  llm_provider: :openai,
  llm_options: %{model: "gpt-3.5-turbo"},
  system_prompt: "You are a helpful assistant with access to weather info and memory",
  tools: ["weather", "memory_tool"]
})

# Run the agent
{:ok, result} = Adk.run(agent, "What's the weather in London? Remember this for later.")

# The agent will use the weather tool to get the information and
# the memory tool to store it for future reference
```

### LangChain-powered Agent

```elixir
# Register tools
Adk.register_tool(MyApp.Tools.Weather)
Adk.register_tool(Adk.Tools.MemoryTool)

# Create a LangChain agent
{:ok, agent} = Adk.create_agent(:langchain, %{
  name: "langchain_assistant",
  llm_options: %{
    provider: :anthropic,
    model: "claude-2",
    temperature: 0.5
  },
  system_prompt: "You are a helpful assistant that uses tools to solve problems",
  tools: ["weather", "memory_tool"]
})

# Run the agent
{:ok, result} = Adk.run(agent, "Plan a picnic based on the weather in Paris tomorrow")

# The LangChain agent will use the underlying LangChain library's agent capabilities
# to reason about the query and call the appropriate tools
```

### Multi-Agent System with Memory

```elixir
# Create specialized agents
{:ok, weather_agent} = Adk.create_agent(:llm, %{
  name: :weather_specialist,
  tools: ["weather"]
})

{:ok, travel_agent} = Adk.create_agent(:llm, %{
  name: :travel_specialist,
  tools: ["flights", "hotels"]
})

# Create a coordinator agent
{:ok, coordinator} = Adk.create_agent(:sequential, %{
  name: :trip_planner,
  steps: [
    %{type: "agent", agent: :weather_specialist},
    %{type: "agent", agent: :travel_specialist},
    %{
      type: "function",
      function: fn results ->
        # Store the final plan in memory
        user_id = "user_123"
        Adk.add_to_memory(:in_memory, user_id, results)
        
        # Return formatted results
        "Trip planned! Weather and travel arrangements confirmed."
      end
    }
  ]
})

# Run the coordinator agent
{:ok, result} = Adk.run(coordinator, "Plan a trip to Paris next week")
```

## Agent Types

The ADK supports several types of agents:

- **Sequential**: Executes a series of steps in order, passing results between steps
- **Parallel**: Executes multiple tasks concurrently for improved performance
- **Loop**: Repeats actions until a condition is met
- **LLM**: Uses language models for decision making and tool selection
- **LangChain**: Leverages the LangChain Elixir library for agent capabilities

## Tools

Tools are the primary way for agents to interact with the world. The ADK provides a simple interface for creating and registering tools that can be used by agents.

## Memory

The Memory service allows agents to store and retrieve information across sessions or interactions:

```elixir
# Store information
Adk.add_to_memory(:in_memory, "user_123", "Important information")

# Retrieve stored information
{:ok, sessions} = Adk.get_memory(:in_memory, "user_123")

# Search memory
{:ok, results} = Adk.search_memory(:in_memory, "user_123", "important")
```

## Agent-to-Agent Communication

Agents can communicate with each other either locally or remotely:

```elixir
# Call a local agent
{:ok, result} = Adk.call_agent(weather_agent, "What's the weather in Paris?")

# Make an agent available via HTTP
Adk.expose_agent(weather_agent, "/agents/weather")

# Call a remote agent
{:ok, result} = Adk.call_remote_agent("https://weather-service.example.com/run", 
                                     "What's the weather in Paris?")
```

## Architectural Design

ADK for Elixir follows a modular design based on OTP principles:

```
adk/
├── agent/            # Core agent interfaces and behaviors
│   ├── sequential.ex # Sequential workflow agent
│   ├── parallel.ex   # Parallel execution agent
│   ├── loop.ex       # Repetition-based agent
│   └── llm.ex        # Language model agent
├── memory/           # Memory persistence services
│   ├── in_memory.ex  # Volatile memory storage
│   └── ...           # Other memory backends
├── tool/             # Tool and plugin system
│   ├── registry.ex   # Tool discovery mechanism
│   └── tools/        # Built-in tools
├── a2a.ex            # Agent-to-Agent protocol
├── application.ex    # OTP application setup
└── adk.ex            # Main API module
```

## Contributing

Contributions are welcome! Here are some ways to help:

1. Implement additional agent types
2. Create new tools for specialized domains
3. Build memory backends for external databases 
4. Improve LLM provider implementations and testing
5. Implement A2A protocol with real HTTP communication
6. Improve documentation and examples
7. Report bugs and suggest features

## Documentation

For more detailed documentation and examples, visit the [docs](https://hexdocs.pm/adk).

## Credits

This project is an implementation of Google's [Agent Development Kit](https://developers.googleblog.com/en/agent-development-kit-easy-to-build-multi-agent-applications) architecture in Elixir, adapting it to leverage the Erlang VM's concurrency model and OTP framework.

## License

This project is licensed under the MIT License.