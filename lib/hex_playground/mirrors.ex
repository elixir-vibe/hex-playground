defmodule HexPlayground.Mirrors do
  @moduledoc false

  @default ["https://repo.hex.pm"]

  def default, do: @default

  def parse(nil), do: @default
  def parse([]), do: @default

  def parse(values) when is_list(values) do
    values
    |> Enum.flat_map(&String.split(&1, ",", trim: true))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.trim_trailing(&1, "/"))
    |> case do
      [] -> @default
      mirrors -> Enum.uniq(mirrors)
    end
  end

  def ordered(mirrors, strategy, index) do
    mirrors = parse(mirrors)

    first_index =
      case strategy do
        "random" -> :rand.uniform(length(mirrors)) - 1
        _round_robin -> rem(index, length(mirrors))
      end

    {head, tail} = Enum.split(mirrors, first_index)
    tail ++ head
  end
end
