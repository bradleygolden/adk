defmodule Adk.MixProject do
  use Mix.Project

  def project do
    [
      app: :adk,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Agent Development Kit for Elixir - framework for building AI agents",
      package: package(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        "test.watch": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Adk.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:langchain, "~> 0.3.2", optional: true},
      {:bypass, "~> 2.1", only: :test},
      # Added UUID dependency
      {:uuid, "~> 1.1"},
      # Added mix_test_watch for development and testing
      {:mix_test_watch, "~> 1.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "adk",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bradleygolden/adk"}
    ]
  end

  defp docs do
    [
      main: "Adk",
      extras: ["README.md"]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
