defmodule XaiBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :xai_bot,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {XaiBot.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:sweet_xml, "~> 0.7"}
    ]
  end
end
