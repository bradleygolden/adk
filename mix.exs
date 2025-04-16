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
      docs: docs()
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
      {:jason, "~> 1.4"},
      {:langchain, "~> 0.3.2", optional: true},
      {:meck, "~> 0.9", only: :test}
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
end
