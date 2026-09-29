# ExUnit entry point for `mix test` (see test_paths in mix.exs).
#
# The real checks live in the standalone scripts under test/*.exs, which
# `make test` runs directly with `elixir -r test/test_helper.exs ...`.
# test/exunit/scripts_test.exs runs those same scripts from ExUnit.
ExUnit.start()
