# ADK Overview

ADK (Agent Development Kit) is a framework for building, running, and managing intelligent agents in Elixir. It provides abstractions and utilities for orchestrating workflows, integrating tools, managing memory, and leveraging language models (LLMs).

## What is ADK?

ADK enables you to:
- Compose agents that can reason, call tools, and manage state
- Integrate with LLMs through custom providers
- Build modular, extensible agent systems using Elixir and OTP

## Core Concepts

### Agents
Agents are the primary orchestrators. They can:
- Execute workflows in different patterns:
  - **Sequential**: Execute steps in order, passing results between them
  - **Parallel**: Run multiple tasks concurrently and collect results
  - **Loop**: Repeat steps until a condition is met
- Use LLMs for reasoning and tool selection
- Run as supervised OTP processes

See [Agent Types](agent_types.md) for details.

### Tools
Tools are modules that perform actions or computations. Agents invoke tools to:
- Call external APIs
- Perform calculations
- Access or update memory

Tools implement the `Adk.Tool` behavior and are registered with the `Adk.ToolRegistry`.

See [Tools Guide](tools.md) for how to define and use tools.

### Memory
Memory allows agents to persist state and history across interactions. ADK provides:
- In-memory session storage
- Event-based history tracking
- Functions for accessing and updating shared state

See [Memory Guide](memory.md) for usage.

### Event System
The event system tracks all agent activities:
- Messages between agent and user
- Tool calls and results
- Agent state changes
- Error conditions

Events are stored in memory and can be retrieved for debugging or auditing.

### PromptTemplates
For LLM-based agents, ADK includes a prompt templating system to:
- Format messages for LLM providers
- Include tool definitions in prompts
- Maintain conversation history
- Support different prompt styles

## How It Fits Together

1. **Define tools** for external actions using the `Adk.Tool` behavior.
2. **Register tools** with `Adk.register_tool/1`.
3. **Create agents** with `Adk.create_agent/2`, configuring their steps and tools.
4. **Run agents** with `Adk.run/2` or `Adk.run/3` to include session data.
5. **Access memory** with `Adk.Memory` functions to retrieve or update state.

## Architecture Summary

- **Agents**: Orchestrate logic and workflows
- **Tools**: Encapsulate actions and integrations
- **Memory**: Store session data and event history
- **Events**: Track and record all system activities
- **OTP**: Ensures concurrency, fault-tolerance, and scalability

## Next Steps

- [Getting Started](../getting_started.md)
- [Agent Types](agent_types.md)
- [Tools](tools.md)
- [Memory](memory.md) 