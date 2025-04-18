# Memory in ADK

Memory in ADK allows agents to persist state, track history, and recall information across interactions. This enables more context-aware and capable agents.

## What is Memory?

Memory is a service that stores session data and event history for agents. It can be used to:
- Track conversation or workflow history
- Store intermediate or final results
- Enable agents to "remember" facts or user preferences

## In-Memory Session Storage

By default, ADK provides an in-memory backend for fast, volatile storage. Each session is identified by a unique `session_id` (e.g., user ID, conversation ID).

## Event-Based History

ADK stores events (messages, tool calls, results) as a sequence of `Adk.Event` structs. This enables:
- Full replay of agent interactions
- Auditing and debugging
- Building persistent or distributed memory backends in the future

## Basic Memory Operations

### Add Data to Memory

```elixir
:ok = Adk.Memory.add(:in_memory, "user_123", %{key: "value"})
```

### Retrieve Session Data

```elixir
{:ok, data} = Adk.Memory.get(:in_memory, "user_123")
IO.inspect(data)
```

### Update Memory

```elixir
:ok = Adk.Memory.update(:in_memory, "user_123", fn existing_data ->
  Map.put(existing_data, :counter, (existing_data[:counter] || 0) + 1)
end)
```

### Clear Session Data

```elixir
:ok = Adk.Memory.clear(:in_memory, "user_123")
```

## Working with Message History

The memory system provides specialized functions for managing conversation history:

### Add a Message

```elixir
:ok = Adk.Memory.add_message(:in_memory, "session_abc", %{
  role: :user,
  content: "What's the weather?",
  timestamp: DateTime.utc_now()
})
```

### Add a Tool Result

```elixir
:ok = Adk.Memory.add_tool_result(:in_memory, "session_abc", %{
  tool_name: "weather",
  result: "It's sunny in Tokyo",
  timestamp: DateTime.utc_now()
})
```

### Get Message History

```elixir
{:ok, messages} = Adk.Memory.get_messages(:in_memory, "session_abc")
IO.inspect(messages)
```

## Event System

The Adk.Event module defines event structs for various interactions:

```elixir
# Create a user message event
event = %Adk.Event{
  type: :message,
  data: %{
    role: :user,
    content: "Hello agent"
  },
  metadata: %{timestamp: DateTime.utc_now()}
}

# Add the event to memory
:ok = Adk.Memory.add_event(:in_memory, "session_id", event)

# Get all events
{:ok, events} = Adk.Memory.get_events(:in_memory, "session_id")
```

## Memory in Agents

Agents automatically interact with memory when running:

```elixir
{:ok, agent} = Adk.create_agent(:sequential, %{
  name: "memory_agent",
  steps: [
    %{
      type: "function",
      function: fn _input, memory ->
        # Access memory data
        counter = memory[:counter] || 0
        
        # Update memory (will be saved after function returns)
        {:ok, "Current count: #{counter}", %{counter: counter + 1}}
      end
    }
  ]
})

# Run multiple times with the same session ID
{:ok, result1} = Adk.run(agent, nil, %{session_id: "test_session"})
{:ok, result2} = Adk.run(agent, nil, %{session_id: "test_session"})
{:ok, result3} = Adk.run(agent, nil, %{session_id: "test_session"})

# Output shows increasing counter
IO.puts(result1.output) # => "Current count: 0"
IO.puts(result2.output) # => "Current count: 1"
IO.puts(result3.output) # => "Current count: 2"
```

## Best Practices

- Use unique, stable session IDs for each user or conversation.
- Regularly clear or archive old sessions if using in-memory storage.
- When tracking conversations, include timestamps for proper ordering.
- Design functions to handle missing or incomplete memory gracefully.

For more examples, see the `examples/` directory.

## Pluggable Backends (Future)

- The default backend is in-memory (volatile).
- Persistent backends (e.g., Redis, Postgres) can be added for durability and scaling.
- You can implement your own backend by following the `Adk.Memory` behaviour.

## Troubleshooting

- If memory is lost on restart, switch to or implement a persistent backend.
- Ensure session IDs are unique to avoid data collisions.

## More

- See [Agent Types](agent_types.md) for how agents use memory.
- See [Examples](../../examples/) for practical usage patterns. 