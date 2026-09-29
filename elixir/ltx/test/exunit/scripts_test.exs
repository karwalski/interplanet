defmodule InterplanetLtx.ScriptsTest do
  @moduledoc """
  Runs each standalone check script in test/ (the same ones `make test`
  runs) as an ExUnit test, so `mix test` covers identical assertions.

  Each script is run in its own `elixir` process because the scripts
  `Code.require_file/2` the library sources themselves; loading them into
  the Mix VM (where lib/ is already compiled) would redefine modules.
  A script passes when it exits 0 and reports "N passed  0 failed".
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  @scripts [
    {"LTX unit tests", "test/interplanet_ltx_test.exs"},
    {"Security tests (Epic 29)", "test/security_test.exs"},
    {"LTX v1.1 core subset tests (Epic 72)", "test/v11_test.exs"},
    {"JS reference parity tests (issue #27)", "test/parity_test.exs"}
  ]

  for {name, script} <- @scripts do
    @script script
    @tag timeout: 300_000
    test name do
      elixir = System.find_executable("elixir") || flunk("elixir executable not found on PATH")

      {out, status} =
        System.cmd(elixir, ["-r", "test/test_helper.exs", @script],
          cd: @root,
          stderr_to_stdout: true
        )

      fails =
        out
        |> String.split("\n")
        |> Enum.filter(&String.starts_with?(&1, "FAIL"))

      assert status == 0 and fails == [],
             "#{@script} exited #{status}\n" <> Enum.join(fails, "\n") <> "\n\n" <> tail(out)

      assert [_, passed] = Regex.run(~r/(\d+) passed\s+0 failed/, out),
             "#{@script}: no \"N passed  0 failed\" summary\n" <> tail(out)

      assert String.to_integer(passed) > 0
    end
  end

  defp tail(out), do: out |> String.split("\n") |> Enum.take(-40) |> Enum.join("\n")
end
