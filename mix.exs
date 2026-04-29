defmodule Mnemo.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/getmnemo/getmnemo-elixir"

  def project do
    [
      app: :getmnemo,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "Official Elixir client for the Mnemo memory API.",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:plug, "~> 1.16", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["Mnemo"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
