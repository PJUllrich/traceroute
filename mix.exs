defmodule Traceroute.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/PJUllrich/traceroute"

  def project do
    [
      app: :traceroute,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: "Runs traceroutes and pings natively in Elixir",
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      source_url: @source_url,
      api_reference: false,
      authors: ["Peter Ullrich"],
      assets: %{"assets" => "assets"},
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp package do
    [
      name: "traceroute",
      files: ~w(lib .formatter.exs mix.exs .credo.exs .iex.exs README* LICENSE*
                CHANGELOG*),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
