defmodule Adk.Config do
  @moduledoc """
  Configuration management for the ADK.
  Provides a runtime interface to application configuration.
  """

  @doc """
  Set a configuration value at runtime.
  """
  def set(key, value) do
    Application.put_env(:adk, key, value)
  end

  @doc """
  Get a configuration value.
  """
  def get(key, default \\ nil) do
    Application.get_env(:adk, key, default)
  end
end
