defmodule AshSumType.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_sum_type,
      version: "1.0.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev,
      usage_rules: usage_rules()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash, "~> 3.0"}
    ]
  end

  defp usage_rules do
    []
  end
end
