defmodule HexPlayground.MixProject do
  use Mix.Project

  def project do
    [
      app: :hex_playground,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: HexPlayground.CLI]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:hex_core, "~> 0.15"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"}
    ]
  end
end
