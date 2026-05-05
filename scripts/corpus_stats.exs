#!/usr/bin/env elixir
Mix.install([{:jason, "~> 1.4"}])

manifest = "manifest.json" |> File.read!() |> Jason.decode!()
entries = Enum.filter(manifest["entries"], &(&1["status"] == "ok"))

counts =
  Enum.reduce(entries, %{}, fn entry, acc ->
    Enum.reduce(entry["language_counts"] || %{}, acc, fn {ext, count}, acc ->
      Map.update(acc, ext, count, &(&1 + count))
    end)
  end)

top_extensions =
  counts
  |> Enum.sort_by(fn {_ext, count} -> -count end)
  |> Enum.take(30)
  |> Enum.map(fn {ext, count} -> %{extension: ext, files: count} end)

summary = %{
  packages: length(entries),
  files: Enum.sum(Map.values(counts)),
  top_extensions: top_extensions
}

IO.puts(Jason.encode!(summary, pretty: true))
