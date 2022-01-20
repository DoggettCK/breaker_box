defmodule BreakerBox.MixProject do
  use Mix.Project

  def project do
    [
      app: :breaker_box,
      build_embedded: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      docs: docs(),
      elixir: "~> 1.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "BreakerBox",
      package: package(),
      source_url: "https://github.com/DoggettCK/breaker_box",
      start_permanent: Mix.env() == :prod,
      version: "0.3.1"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :fuse]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:behave, ">= 0.1.0"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.27.3", only: :dev, runtime: false},
      {:fuse, "~> 2.5"},
      {:mix_test_watch, "~> 1.1", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "`BreakerBox` is an implementation of the circuit breaker pattern, " <>
      "wrapping the Fuse Erlang library with a supervised server for ease " <>
      "of breaker configuration and management."
  end

  defp package() do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/DoggettCK/breaker_box"},
      maintainers: ["Chris Doggett"]
    ]
  end

  defp docs() do
    [
      main: "BreakerBox",
      source_url: "https://github.com/DoggettCK/breaker_box"
    ]
  end
end
