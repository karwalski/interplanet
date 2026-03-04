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
