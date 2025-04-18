# Weather Agent Example

This example demonstrates how to build a simple weather agent using the ADK (Agent Development Kit for Elixir). The agent will fetch the current weather for a given city using a custom tool.

## Goal
Build an agent that takes a city name as input and returns the current weather for that city.

---

## 1. Project Setup

Create a new Mix project:

```sh
mix new weather_agent
cd weather_agent
```

Add `:adk` to your `mix.exs` dependencies:

```elixir
defp deps do
  [
    {:adk, "~> 0.1.0"}
  ]
end
```

Fetch dependencies:

```sh
mix deps.get
```

---

## 2. Define a Weather Tool

Create `lib/weather_tool.ex`:

```elixir
defmodule WeatherTool do
  use Adk.Tool

  @impl true
  def definition do
    %{
      name: "weather",
      description: "Get the current weather for a city",
      parameters: %{
        city: %{
          type: "string",
          description: "The city to get weather for"
        }
      }
    }
  end

  @impl true
  def execute(%{"city" => city}, _context) do
    # For demo, return fake weather. Replace with real API call as needed.
    {:ok, "It's sunny in #{city}!"}
  end
end
```

---

## 3. Define the Weather Agent

Create `lib/weather_agent.ex`:

```elixir
defmodule WeatherAgent do
  def create do
    # Register the tool
    Adk.register_tool(WeatherTool)
    
    # Create a sequential agent that uses the weather tool
    Adk.create_agent(:sequential, %{
      name: "weather_agent",
      steps: [
        %{
          type: "tool",
          tool: "weather",
          params: fn input -> %{"city" => input} end
        }
      ]
    })
  end
  
  def run(city) do
    {:ok, agent} = create()
    {:ok, result} = Adk.run(agent, city)
    IO.puts("Weather: #{result.output}")
    result.output
  end
end
```

---

## 4. Run the Agent

Create a simple script in `lib/run.ex`:

```elixir
defmodule Run do
  def main do
    city = IO.gets("Enter a city: ") |> String.trim()
    WeatherAgent.run(city)
  end
end
```

Then run:

```sh
mix run -e 'Run.main()'
```

---

## 5. Expected Output

```
Enter a city: Tokyo
Weather: It's sunny in Tokyo!
```

---

## 6. Advanced: Using Memory

You can enhance the weather agent to remember previous searches:

```elixir
defmodule WeatherAgentWithMemory do
  def create do
    Adk.register_tool(WeatherTool)
    
    Adk.create_agent(:sequential, %{
      name: "weather_memory_agent",
      steps: [
        %{
          type: "function",
          function: fn input, memory ->
            # Retrieve previous searches
            previous = Map.get(memory, :previous_searches, [])
            
            # Add current city to previous searches
            updated_memory = %{
              previous_searches: [input | previous] |> Enum.take(5)
            }
            
            # Pass the input forward and update memory
            {:ok, input, updated_memory}
          end
        },
        %{
          type: "tool",
          tool: "weather",
          params: fn input -> %{"city" => input} end
        },
        %{
          type: "function",
          function: fn output, memory ->
            previous = Map.get(memory, :previous_searches, [])
            
            message = """
            #{output}
            
            Previous searches: #{Enum.join(previous, ", ")}
            """
            
            {:ok, message}
          end
        }
      ]
    })
  end
  
  def run(city, session_id \\ "default") do
    {:ok, agent} = create()
    {:ok, result} = Adk.run(agent, city, %{session_id: session_id})
    IO.puts(result.output)
    result.output
  end
end
```

Try running this agent multiple times with the same session ID to see how it builds up memory. 