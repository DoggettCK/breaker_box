defmodule BreakerBox.MixProject do
  use Mix.Project

  def project do
    [
      app: :breaker_box,
      version: "0.1.0",
      elixir: "~> 1.0",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      name: "BreakerBox",
      source_url: "https://github.com/DoggettCK/breaker_box",
      package: package(),
      docs: docs(),
      deps: deps()
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
      {:credo, "~> 0.10", override: true},
      {:ex_doc, "~> 0.20", only: :dev, runtime: false},
      {:fuse, "~> 2.4"},
      {:mix_test_watch, "~> 0.5", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    # TODO: Description
    ""
  end

  defp package() do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Chris Doggett"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/DoggettCK/breaker_box"}
    ]
  end

  defp docs() do
    [
      main: "BreakerBox",
      source_url: "https://github.com/DoggettCK/breaker_box"
    ]
  end
end
