# Adk Callback System

The Adk Callback System allows you to inject custom behavior at various points in the agent lifecycle. This provides a powerful way to extend and customize agent functionality without modifying the core framework code.

## Callback Types

The framework supports the following callback types:

- `:before_run` - Executed before an agent processes input
- `:after_run` - Executed after an agent has processed input and produced output
- `:before_llm_call` - Executed before making a call to the LLM
- `:after_llm_call` - Executed after receiving a response from the LLM
- `:before_tool_call` - Executed before invoking a tool
- `:after_tool_call` - Executed after a tool returns a result
- `:on_error` - Executed when an error occurs during processing

## Basic Usage

### Registering Callbacks

```elixir
# Register a global callback for all agents
Adk.Callback.register(:before_run, fn input, context ->
  IO.puts("About to run agent with input: #{inspect(input)}")
  {:cont, input}
end)

# Register a callback for a specific agent
Adk.Callback.register(:after_run, fn output, context ->
  IO.puts("Agent #{context.agent_name} produced: #{inspect(output)}")
  {:cont, output}
end, %{agent_name: "my_agent"})
```

### Using Helper Functions

The `Adk.Callback.Helpers` module provides pre-built callback functions for common patterns:

```elixir
# Add a logging callback
Adk.Callback.register(
  :before_run, 
  Adk.Callback.Helpers.log_callback("Processing input")
)

# Add a callback that transforms the input
Adk.Callback.register(
  :before_run, 
  Adk.Callback.Helpers.transform_callback(fn input, _ctx -> 
    # Add a timestamp to the input
    Map.put(input, :timestamp, DateTime.utc_now())
  end)
)

# Add validation to prevent empty inputs
Adk.Callback.register(
  :before_run, 
  Adk.Callback.Helpers.validate_callback(
    &(!is_nil(&1) && &1 != ""), 
    "Input cannot be empty"
  )
)
```

## Common Use Cases

### Input Preprocessing

```elixir
Adk.Callback.register(:before_run, fn input, _context ->
  # Normalize input to lowercase string
  input = if is_binary(input), do: String.downcase(input), else: input
  
  # Add context information
  input = if is_map(input), do: Map.put(input, :timestamp, DateTime.utc_now()), else: input
  
  {:cont, input}
end)
```

### Monitoring and Logging

```elixir
# Log all LLM calls
Adk.Callback.register(:before_llm_call, fn messages, context ->
  Logger.info("LLM call to #{inspect(context.llm_provider)} with #{length(messages)} messages")
  {:cont, messages}
end)

# Log all tool calls
Adk.Callback.register(:before_tool_call, fn tool_data, context ->
  Logger.info("Tool call: #{tool_data.name} with args: #{inspect(tool_data.args)}")
  {:cont, tool_data}
end)

# Track agent performance with telemetry
Adk.Callback.register(
  :after_run, 
  Adk.Callback.Helpers.telemetry_callback(
    [:adk, :agent, :completion], 
    fn _output, context -> 
      %{timestamp: System.system_time(:millisecond)} 
    end
  )
)
```

### Content Filtering

```elixir
# Filter profanity or sensitive information from LLM responses
Adk.Callback.register(:after_llm_call, fn response, _context ->
  modified_content = filter_sensitive_content(response.content)
  modified_response = Map.put(response, :content, modified_content)
  {:cont, modified_response}
end)

# Filter potentially unsafe tool calls
Adk.Callback.register(:before_tool_call, fn tool_data, _context ->
  if is_unsafe_tool_call?(tool_data) do
    # Halt the chain with a safe response
    {:halt, "This operation is not permitted for security reasons."}
  else
    {:cont, tool_data}
  end
end)
```

### Caching

```elixir
# Cache LLM responses to avoid duplicate calls
Adk.Callback.register(:before_llm_call, fn messages, context ->
  cache_key = "llm:#{compute_hash(messages)}"
  
  case Adk.Memory.get(context.session_id, cache_key) do
    {:ok, cached_response} ->
      # Halt chain with cached response
      {:halt, cached_response}
    _ ->
      # Continue with original messages
      {:cont, messages}
  end
end)

# Cache responses after receiving them
Adk.Callback.register(
  :after_llm_call, 
  Adk.Callback.Helpers.cache_callback(fn response, context -> 
    "llm_response:#{context.invocation_id}"
  end)
)
```

## Advanced Patterns

### Pipeline Processing

You can register multiple callbacks of the same type to create a processing pipeline:

```elixir
# First callback lowercases the input
Adk.Callback.register(:before_run, fn input, _context ->
  {:cont, String.downcase(input)}
end)

# Second callback trims whitespace
Adk.Callback.register(:before_run, fn input, _context ->
  {:cont, String.trim(input)}
end)

# Third callback adds metadata
Adk.Callback.register(:before_run, fn input, context ->
  {:cont, %{text: input, agent: context.agent_name, timestamp: DateTime.utc_now()}}
end)
```

### Error Recovery

You can use the `:on_error` callback to handle and potentially recover from errors:

```elixir
Adk.Callback.register(:on_error, fn error, context ->
  Logger.error("Error in agent #{context.agent_name}: #{inspect(error)}")
  
  case error do
    {:error, {:llm_execution_error, _}} ->
      # Return a fallback response for LLM errors
      {:halt, {:ok, %{output: "I'm having trouble connecting to my knowledge service. Please try again later."}}}
      
    {:error, {:tool_execution_error, _}} ->
      # Return a fallback for tool errors
      {:halt, {:ok, %{output: "I couldn't complete that operation. Please try a different approach."}}}
      
    _ ->
      # Pass through other errors
      {:cont, error}
  end
end)
```

### Dynamic Registration

You can create functions that register callbacks based on configuration:

```elixir
def setup_agent_callbacks(agent_name, config) do
  # Register basic logging
  Adk.Callback.register(:before_run, Adk.Callback.Helpers.log_callback("Starting agent"), %{agent_name: agent_name})
  
  # Conditionally enable other callbacks
  if config.enable_caching do
    Adk.Callback.register(:after_llm_call, cache_callback(), %{agent_name: agent_name})
  end
  
  if config.content_filter do
    Adk.Callback.register(:after_llm_call, content_filter_callback(), %{agent_name: agent_name})
  end
  
  :ok
end
```

## Best Practices

1. **Keep callbacks focused**: Each callback should do one thing well.
2. **Consider performance**: Especially for callbacks that run frequently.
3. **Handle errors**: Always handle potential errors in your callbacks.
4. **Use context for filtering**: Target callbacks to specific agents or scenarios.
5. **Use helper functions**: Leverage the `Adk.Callback.Helpers` module for common patterns.
6. **Test your callbacks**: Write tests for your callback functions to ensure they work as expected. 