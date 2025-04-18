defmodule Adk.Agent.LLM do
  @moduledoc """
  LLM agent that delegates execution to a pluggable backend (e.g., LangChain).
  Implements the Adk.Agent behaviour.
  """
  @behaviour Adk.Agent
  require Logger

  defstruct [
    :model,
    :tools,
    :system_prompt,
    :name,
    :llm_provider,
    :session_id,
    :invocation_id,
    prompt_builder: Adk.Agent.Llm.PromptBuilder.Default,
    llm_options: %{},
    backend: Adk.Agent.LLM.LangchainBackend
  ]

  @doc """
  Returns the module to use for this agent.
  This is needed for Server to correctly identify the agent module.
  """
  def __agent_module__, do: __MODULE__

  @doc """
  Creates a new LLM agent struct after validation.
  """
  def new(config_map) when is_map(config_map) do
    validate_and_build_config(config_map)
  end

  @impl true
  def run(%__MODULE__{backend: backend_mod} = agent, input) when is_atom(backend_mod) do
    backend_mod.run(agent, input)
  end

  @doc """
  Starts the LLM agent as a GenServer process using Adk.Agent.Server.
  This allows the struct-based LLM agent to work with the supervisor.
  """
  def start_link(config, opts \\ []) do
    case new(config) do
      {:ok, llm_config} ->
        Adk.Agent.Server.start_link(llm_config, opts)

      {:error, _reason} = error ->
        error
    end
  end

  # --- Private Functions ---

  # Config Validation
  defp validate_and_build_config(config_map) do
    required_keys = [:name, :llm_provider]
    missing_keys = Enum.filter(required_keys, &(!Map.has_key?(config_map, &1)))

    if !Enum.empty?(missing_keys) do
      {:error, {:invalid_config, :missing_keys, missing_keys}}
    else
      try do
        # Set defaults for optional fields
        defaults = %{
          tools: [],
          llm_options: %{},
          system_prompt: "You are a helpful assistant.",
          prompt_builder: Adk.Agent.Llm.PromptBuilder.Default,
          backend: Adk.Agent.LLM.LangchainBackend
        }

        config_with_defaults = Map.merge(defaults, config_map)
        config = struct!(__MODULE__, config_with_defaults)

        with :ok <- validate_llm_provider(config.llm_provider),
             :ok <- validate_tools(config.tools),
             :ok <- validate_prompt_builder(config.prompt_builder) do
          {:ok, config}
        else
          {:error, reason} -> {:error, reason}
        end
      rescue
        ArgumentError ->
          {:error, {:invalid_config, :struct_conversion_failed, config_map}}

        e ->
          {:error, {:invalid_config, :unexpected_error, e}}
      end
    end
  end

  defp validate_llm_provider(provider) do
    cond do
      is_atom(provider) and function_exported?(provider, :chat, 2) -> :ok
      is_atom(provider) -> {:error, {:invalid_config, :llm_provider_missing_chat, provider}}
      true -> {:error, {:invalid_config, :invalid_llm_provider_type, provider}}
    end
  end

  # Basic check, deeper validation in ToolRegistry/LLM
  defp validate_tools(tools) when is_list(tools), do: :ok
  defp validate_tools(other), do: {:error, {:invalid_config, :invalid_tools_type, other}}

  defp validate_prompt_builder(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :build_messages, 1) do
      :ok
    else
      {:error, {:invalid_config, :invalid_prompt_builder, {module, :build_messages, 1}}}
    end
  end

  defp validate_prompt_builder(other) do
    {:error, {:invalid_config, :invalid_prompt_builder_type, other}}
  end
end
