# Agent Types in ADK

ADK supports several agent types, each suited for different orchestration and reasoning patterns. This guide covers the main types, their use cases, configuration, and example usage.

## Sequential Agent

**What & Why:**
- Executes a series of steps in order, passing results between steps.
- Use for workflows where each step depends on the previous one.

**Configuration:**
- `:name` (atom/string) — unique agent name
- `:steps` (list) — ordered list of steps (function, tool, or agent)

**Example:**
```elixir
{:ok, agent} = Adk.create_agent(:sequential, %{
  name: "echo_agent",
  steps: [
    %{type: "function", function: fn input -> "Echo: #{input}" end}
  ]
})
{:ok, result} = Adk.run(agent, "Test")
IO.puts(result.output) # => "Echo: Test"
```

**Notes:**
- Steps can be functions, tool calls, or sub-agents.
- Errors in a step halt execution and return an error tuple.
- Each step receives the output of the previous step as input.

---

## Parallel Agent

**What & Why:**
- Runs multiple tasks concurrently and collects their results.
- Use for independent tasks that can be performed in parallel.

**Configuration:**
- `:name` (atom/string)
- `:tasks` (list) — tasks to run in parallel
- `:halt_on_error` (boolean, default: true) — whether to stop all tasks if one fails
- `:task_timeout` (integer, optional) — timeout in milliseconds for each task

**Example:**
```elixir
{:ok, agent} = Adk.create_agent(:parallel, %{
  name: "math_agent",
  tasks: [
    %{type: "function", function: fn _ -> "Task 1 result" end},
    %{type: "function", function: fn _ -> "Task 2 result" end}
  ]
})
{:ok, result} = Adk.run(agent, nil)
IO.inspect(result.output) # => %{0 => "Task 1 result", 1 => "Task 2 result"}
IO.inspect(result.combined) # => "Task 1 result\nTask 2 result"
```

**Notes:**
- Each task runs in its own process.
- Results are collected as a map with task indices as keys.
- A `combined` field provides a simple joined representation of all results.
- If `halt_on_error: false`, execution continues even if some tasks fail.

---

## Loop Agent

**What & Why:**
- Repeats steps until a condition is met.
- Use for polling, retries, or iterative improvement.

**Configuration:**
- `:name` (atom/string)
- `:steps` (list) — the steps to repeat
- `:condition` (function) — predicate to determine when to stop
- `:max_iterations` (integer) — maximum number of iterations to prevent infinite loops

**Example:**
```elixir
{:ok, agent} = Adk.create_agent(:loop, %{
  name: "counter_agent",
  steps: [
    %{
      type: "function", 
      function: fn input -> 
        count = String.to_integer(input)
        "#{count + 1}" 
      end
    }
  ],
  condition: fn output, _memory ->
    count = String.to_integer(output)
    count >= 5
  end,
  max_iterations: 10
})
{:ok, result} = Adk.run(agent, "0")
IO.inspect(result.output) # => "5"
IO.inspect(result.status) # => :condition_met
```

**Notes:**
- The `:condition` function receives the output of each iteration and memory state.
- The agent stops when either the condition is met or max_iterations is reached.
- The result includes a `:status` field indicating why the loop stopped.

---

## LLM Agent

**What & Why:**
- Uses a language model (LLM) for reasoning, tool selection, and response generation.
- Use for natural language tasks, tool-calling, or complex reasoning.

**Configuration:**
- `:name` (atom/string)
- `:llm_provider` (module) — module that provides LLM functionality
- `:tools` (list, optional) — tool specifications available to the agent
- `:prompt_builder` (module, optional) — module to format prompts

**Example:**
```elixir
defmodule MockLLMProvider do
  def chat(messages, _opts) do
    {:ok, %{content: "I'm a mock LLM response", tool_calls: []}}
  end
end

{:ok, agent} = Adk.create_agent(:llm, %{
  name: "assistant",
  llm_provider: MockLLMProvider,
  prompt_builder: Adk.Agent.Llm.PromptBuilder.Default
})
{:ok, result} = Adk.run(agent, "Hello")
IO.inspect(result.content) # => "I'm a mock LLM response"
```

**Notes:**
- Tool-calling is supported if tools are registered and listed.
- The response format includes fields for content, tool calls, and tool results.
- Can integrate with any LLM provider that follows the expected interface.

---

## LangChain Agent

**What & Why:**
- Integrates with the LangChain Elixir library for advanced LLM and tool workflows.
- Use for leveraging LangChain's features and provider support.

**Configuration:**
- `:name` (atom/string)
- `:llm_options` (map) — must include provider/model
- `:system_prompt` (string)
- `:tools` (list, optional)

**Example:**
```elixir
{:ok, agent} = Adk.create_agent(:langchain, %{
  name: :my_langchain_agent,
  llm_options: %{
    provider: :openai,
    model: "gpt-4"
  },
  system_prompt: "You are a helpful assistant.",
  tools: ["weather"]
})
{:ok, result} = Adk.run(agent, "Plan a picnic based on the weather in Paris tomorrow")
IO.inspect(result.output)
```

**Notes:**
- Requires the `:langchain` dependency.
- Handles tool-calling and LLM reasoning via LangChain.

---

## Using Agents with OTP

All agents can be run as supervised OTP processes:

```elixir
# Create the agent struct
{:ok, agent_struct} = Adk.Agent.Sequential.new(config)

# Start as a GenServer process
{:ok, pid} = Adk.Agent.Server.start_link(agent_struct)

# Run the agent through the server
{:ok, result} = Adk.Agent.Server.run(pid, "input")
```

For more examples, see the `examples/` directory. 