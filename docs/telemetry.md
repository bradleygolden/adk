# Adk Telemetry

The Adk framework provides a comprehensive telemetry system to help you monitor and observe the behavior of your agents in real-time. This guide will help you understand how to use telemetry in your Adk applications.

## Overview

Adk uses `:telemetry`, a standardized approach to metrics and instrumentation in Elixir applications. All telemetry events emitted by the Adk framework follow a consistent naming convention:

```
[:adk, <component>, <action>, <stage>]
```

Where:
- `<component>` is the part of the framework emitting the event (e.g., `:agent`, `:llm`, `:tool`)
- `<action>` is the operation being performed (e.g., `:run`, `:call`)
- `<stage>` is the stage of the operation (`:start`, `:stop`, or `:exception`)

## Standard Telemetry Events

The framework emits the following standard events:

### Agent Events

- `[:adk, :agent, :run, :start]` - When an agent begins processing input
- `[:adk, :agent, :run, :stop]` - When an agent completes processing
- `[:adk, :agent, :run, :exception]` - When an agent raises an exception

### LLM Events

- `[:adk, :llm, :call, :start]` - When an LLM call begins
- `[:adk, :llm, :call, :stop]` - When an LLM call completes
- `[:adk, :llm, :call, :exception]` - When an LLM call raises an exception

### Tool Events

- `[:adk, :tool, :call, :start]` - When a tool call begins
- `[:adk, :tool, :call, :stop]` - When a tool call completes
- `[:adk, :tool, :call, :exception]` - When a tool call raises an exception

## Telemetry Measurements

Each telemetry event includes useful measurements:

### Start Events

- `system_time` - System time when the event was emitted

### Stop Events

- `duration` - Duration of the operation in milliseconds
- `monotonic_time` - Monotonic time when the operation completed
- `system_time` - System time when the event was emitted

### Exception Events

- `duration` - Duration until the exception was raised in milliseconds
- `monotonic_time` - Monotonic time when the exception was raised
- `system_time` - System time when the event was emitted

## Telemetry Metadata

Each event includes contextual metadata:

### Agent Metadata

- `agent_name` - Name of the agent
- `agent_module` - Module of the agent
- `session_id` - Agent session ID
- `invocation_id` - Unique ID for this invocation

### LLM Metadata

- `agent_name` - Name of the agent
- `session_id` - Agent session ID
- `invocation_id` - Unique ID for this invocation
- `llm_provider` - The LLM provider module
- `model` - The LLM model being used
- `message_count` - Number of messages in the prompt

### Tool Metadata

- `agent_name` - Name of the agent
- `session_id` - Agent session ID
- `invocation_id` - Unique ID for this invocation
- `tool_call_id` - Unique ID for this tool call
- `tool_name` - Name of the tool being called

## Using Telemetry in Your Application

### Attaching Handlers

You can attach handlers to Adk telemetry events using the `Adk.Telemetry` module:

```elixir
# Define a handler function
defmodule MyApp.TelemetryHandlers do
  require Logger

  def handle_event([:adk, :agent, :run, :stop], measurements, metadata, _config) do
    Logger.info("""
    Agent completed:
      Name: #{metadata.agent_name}
      Duration: #{measurements.duration}ms
    """)
  end

  def handle_llm_call([:adk, :llm, :call, :stop], measurements, metadata, _config) do
    Logger.info("""
    LLM call completed:
      Provider: #{inspect(metadata.llm_provider)}
      Model: #{metadata.model}
      Duration: #{measurements.duration}ms
    """)
  end
end

# Attach handlers in your application startup
def start(_type, _args) do
  # Attach to individual events
  Adk.Telemetry.attach_handler(
    "my-agent-handler",
    [:adk, :agent, :run, :stop],
    &MyApp.TelemetryHandlers.handle_event/4
  )

  # Or attach to multiple events at once
  Adk.Telemetry.attach_many_handlers(
    "my-llm-handlers",
    Adk.Telemetry.llm_events(),
    &MyApp.TelemetryHandlers.handle_llm_call/4
  )

  # ...rest of your application startup
end
```

### Integration with Telemetry.Metrics

You can easily integrate with the `telemetry_metrics` library to collect metrics:

```elixir
defmodule MyApp.Metrics do
  def metrics do
    [
      # Track agent run durations
      Telemetry.Metrics.distribution(
        "adk.agent.run.duration",
        unit: {:native, :millisecond},
        tags: [:agent_name],
        measurement: fn %{duration: duration} -> duration end,
        reporter_options: [
          buckets: [10, 100, 500, 1000, 5000]
        ]
      ),

      # Count total LLM calls
      Telemetry.Metrics.counter(
        "adk.llm.call.count",
        tags: [:llm_provider, :model]
      ),

      # Track LLM call durations
      Telemetry.Metrics.summary(
        "adk.llm.call.duration",
        unit: {:native, :millisecond},
        tags: [:llm_provider, :model]
      ),

      # Count errors
      Telemetry.Metrics.counter(
        "adk.agent.run.exception",
        tags: [:agent_name]
      )
    ]
  end
end
```

### Integration with TelemetryUI

You can use the `telemetry_ui` package to visualize your metrics in a web dashboard:

```elixir
defmodule MyApp.TelemetryUI do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {TelemetryUI, [
        metrics: MyApp.Metrics.metrics(),
        name: :adk_metrics_dashboard,
        route_prefix: "metrics",
        # ... other TelemetryUI options
      ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## Custom Telemetry Events

You can also emit your own telemetry events using the `Adk.Telemetry` module:

```elixir
# Emit a simple event
Adk.Telemetry.execute(
  [:adk, :custom, :operation], 
  %{value: 42},
  %{context: "some context"}
)

# Use a span to track an operation's duration
Adk.Telemetry.span(
  [:adk, :custom, :operation],
  %{custom_metadata: "value"},
  fn ->
    # Your operation here
    :timer.sleep(100)
    {:ok, "result"}
  end
)
```

## Best Practices

1. **Use descriptive event names** - Follow the `[:adk, component, action, stage]` convention
2. **Include relevant metadata** - Add enough context to make the events useful
3. **Handle exceptions** - Always attach handlers for exception events
4. **Use sampling for high-volume events** - Consider sampling for very frequent events
5. **Keep handlers fast** - Telemetry handlers should be lightweight
6. **Use aggregation** - Aggregate metrics rather than storing raw events 