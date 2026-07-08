# Preload library modules so test scripts can `import` them at compile time
# (modern Elixir compiles a whole .exs before executing its require_file calls — B14).
Code.require_file("../lib/interplanet_ltx/constants.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/models.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/interplanet_ltx.ex", __DIR__)

defmodule Test do
  def check(condition, label) do
    if condition do
      IO.puts("PASS: #{label}")
      Process.put(:passed, Process.get(:passed, 0) + 1)
    else
      IO.puts("FAIL: #{label}")
      Process.put(:failed, Process.get(:failed, 0) + 1)
    end
  end
end
