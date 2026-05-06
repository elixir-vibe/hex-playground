defmodule HexPlayground.MirrorsTest do
  use ExUnit.Case, async: true

  alias HexPlayground.Mirrors

  test "parses repeated and comma-separated mirrors" do
    assert Mirrors.parse([
             "https://repo.hex.pm, https://cdn.jsdelivr.net/hex",
             "https://repo.hex.pm/"
           ]) == [
             "https://repo.hex.pm",
             "https://cdn.jsdelivr.net/hex"
           ]
  end

  test "round robin rotates fallback order" do
    mirrors = ["a", "b", "c"]

    assert Mirrors.ordered(mirrors, "round_robin", 0) == ["a", "b", "c"]
    assert Mirrors.ordered(mirrors, "round_robin", 1) == ["b", "c", "a"]
    assert Mirrors.ordered(mirrors, "round_robin", 2) == ["c", "a", "b"]
  end
end
