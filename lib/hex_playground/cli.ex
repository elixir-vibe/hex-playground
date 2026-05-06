defmodule HexPlayground.CLI do
  @moduledoc false

  alias HexPlayground.{Corpus, Mirrors}

  @switches [
    mode: :string,
    limit: :integer,
    out: :string,
    tarballs: :string,
    manifest: :string,
    registry_url: :string,
    mirror: :keep,
    mirror_strategy: :string,
    concurrency: :integer,
    timeout: :integer,
    force: :boolean,
    prune_non_elixir: :boolean,
    help: :boolean
  ]

  def main(args) do
    case parse(args) do
      {:help, message} ->
        IO.puts(message)

      {:ok, opts} ->
        Corpus.build(opts)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  defp parse(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches, aliases: [h: :help])

    cond do
      invalid != [] ->
        {:error, "invalid options: #{inspect(invalid)}\n\n#{usage()}"}

      Keyword.get(opts, :help, false) ->
        {:help, usage()}

      rest not in [[], ["fetch"]] ->
        {:error, "unknown command/options: #{Enum.join(rest, " ")}\n\n#{usage()}"}

      true ->
        {:ok, build_opts(opts)}
    end
  end

  defp build_opts(opts) do
    root = File.cwd!()

    mirrors =
      opts
      |> Keyword.get_values(:mirror)
      |> Mirrors.parse()

    %{
      root: root,
      mode: Keyword.get(opts, :mode, "latest"),
      limit: Keyword.get(opts, :limit),
      out: expand_path(Keyword.get(opts, :out, "sources"), root),
      tarballs: expand_path(Keyword.get(opts, :tarballs, "tarballs"), root),
      manifest: expand_path(Keyword.get(opts, :manifest, "manifest.json"), root),
      registry_url:
        opts |> Keyword.get(:registry_url, "https://repo.hex.pm") |> String.trim_trailing("/"),
      mirrors: mirrors,
      mirror_strategy: Keyword.get(opts, :mirror_strategy, "round_robin"),
      concurrency: Keyword.get(opts, :concurrency, 8),
      timeout: Keyword.get(opts, :timeout, 120_000),
      force: Keyword.get(opts, :force, false),
      prune_non_elixir: Keyword.get(opts, :prune_non_elixir, false)
    }
  end

  defp expand_path(path, root) do
    if Path.type(path) == :absolute, do: path, else: Path.expand(path, root)
  end

  defp usage do
    """
    Usage:
      mix hex_playground.fetch [options]
      mix escript.build && ./hex_playground [fetch] [options]

    Options:
      --mode latest|all|top        Corpus selection. latest uses /versions. top uses Hex API downloads. Default: latest
      --limit N                   Limit selected releases. Default: all for latest/all, 300 for top
      --concurrency N             Concurrent package downloads/extractions. Default: 8
      --timeout MS                Per-download timeout. Default: 120000
      --out DIR                   Extracted source directory. Default: sources
      --tarballs DIR              Tarball cache directory. Default: tarballs
      --manifest PATH             Manifest path. Default: manifest.json
      --registry-url URL          Registry source for /versions. Default: https://repo.hex.pm
      --mirror URL                Tarball mirror. May be repeated or comma-separated.
                                 Default: https://repo.hex.pm
      --mirror-strategy STRATEGY  round_robin or random. Default: round_robin
      --prune-non-elixir         Delete extracted packages with no .ex/.exs files
      --force                     Redownload/re-extract existing entries

    Mirror balancing applies to tarball downloads only. Registry discovery stays on --registry-url.
    Unofficial mirrors should only be used for public tarballs.
    """
  end
end
