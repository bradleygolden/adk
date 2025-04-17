ExUnit.start()

# Start the mock LLM state agent for tests that need it
{:ok, _pid} = Adk.Test.MockLLMStateAgent.start_link(%{})

Mox.defmock(Adk.LLM.Provider.Mock, for: Adk.LLM.Provider)
Mox.defmock(Adk.LLM.Providers.LangchainMock, for: Adk.LLM.Provider)
Mox.defmock(Adk.LLM.Providers.OpenAIMock, for: Adk.LLM.Provider)

ExUnit.configure(capture_log: true)
