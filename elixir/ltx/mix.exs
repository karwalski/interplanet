defmodule InterplanetLtx.MixProject do
  use Mix.Project

  def project do
    [
      app: :interplanet_ltx,
      version: "1.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: [],
      # The scripts in test/*.exs are standalone (run by `make test`);
      # test/exunit wraps them so `mix test` runs the same checks.
      test_paths: ["test/exunit"]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end
end
