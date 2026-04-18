defmodule AshSumType.MixProject do
  use Mix.Project

  @app :ash_sum_type
  @description "A DSL for defining custom Ash types that behave like algebraic sum types."
  @version "1.0.3"
  def project do
    [
      app: @app,
      description: @description,
      version: @version,
      package: package(),
      docs: &docs/0,
      # 
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev
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
      {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash, "~> 3.0"}
    ]
  end

  defp docs do
    [
      extras: [
        "README.md"
      ]
    ]
  end

  defp package do
    [
      maintainers: [
        "Nduati Kuria"
      ],
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* doc),
      links: %{
        "GitHub" => "https://github.com/NduatiK/ash_sum_type"
      }
    ]
  end
end
