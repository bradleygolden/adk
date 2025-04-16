ExUnit.start()

# Start the mock LLM state agent for tests that need it
{:ok, _pid} = Adk.Test.MockLLMStateAgent.start_link(%{})

ExUnit.configure(capture_log: true)
