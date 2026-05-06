defmodule HexPlayground.Corpus do
  @moduledoc false

  alias HexPlayground.{HTTP, Mirrors, Registry}

  def build(opts) do
    File.mkdir_p!(opts.out)
    File.mkdir_p!(opts.tarballs)

    entries = selected_entries(opts)

    manifest_entries =
      entries
      |> Stream.with_index()
      |> Task.async_stream(fn {entry, index} -> fetch_entry(entry, index, opts) end,
        max_concurrency: opts.concurrency,
        timeout: opts.timeout + 30_000,
        ordered: true
      )
      |> Enum.map(fn
        {:ok, entry} -> entry
        {:exit, reason} -> %{status: "error", error: inspect(reason)}
      end)
      |> maybe_prune_non_elixir(opts)

    manifest = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      mode: opts.mode,
      count: Enum.count(manifest_entries, &(&1[:status] == "ok")),
      entries: manifest_entries,
      mirrors: opts.mirrors,
      mirror_strategy: opts.mirror_strategy,
      registry_url: opts.registry_url
    }

    File.write!(opts.manifest, Jason.encode_to_iodata!(manifest, pretty: true))
    IO.puts("Wrote #{Path.relative_to_cwd(opts.manifest)}")
  end

  defp selected_entries(%{mode: "top"} = opts), do: Registry.top(opts.limit || 300, opts.timeout)

  defp selected_entries(opts) do
    opts.registry_url
    |> Registry.versions(opts.timeout)
    |> Registry.select(opts.mode, opts.limit)
  end

  defp fetch_entry(entry, index, opts) do
    slug = "#{entry.name}-#{entry.version}"
    target_dir = Path.join(opts.out, slug)
    tarball = Path.join(opts.tarballs, "#{slug}.tar")

    cond do
      File.dir?(target_dir) and not opts.force ->
        ok_entry(entry, target_dir, tarball, "cached", nil)

      File.exists?(tarball) and not opts.force ->
        File.rm_rf!(target_dir)
        extract_tarball!(tarball, target_dir)
        ok_entry(entry, target_dir, tarball, "extracted", nil)

      true ->
        File.rm_rf!(target_dir)
        mirror = download_tarball!(entry.name, entry.version, tarball, index, opts)
        extract_tarball!(tarball, target_dir)
        ok_entry(entry, target_dir, tarball, "fetched", mirror)
    end
  rescue
    error ->
      %{
        status: "error",
        name: Map.get(entry, :name),
        version: Map.get(entry, :version),
        error: Exception.message(error)
      }
  end

  defp download_tarball!(name, version, tarball, index, opts) do
    path = "/tarballs/#{name}-#{version}.tar"
    mirrors = Mirrors.ordered(opts.mirrors, opts.mirror_strategy, index)
    remove_file(tarball)

    Enum.reduce_while(mirrors, nil, fn mirror, _acc ->
      url = mirror <> path
      IO.puts("Downloading #{name} #{version} from #{mirror}")

      try do
        HTTP.get!(url, into: File.stream!(tarball), timeout: opts.timeout)
        {:halt, mirror}
      rescue
        error ->
          remove_file(tarball)
          IO.puts("Failed #{url}: #{Exception.message(error)}")
          {:cont, nil}
      end
    end) || raise("failed to download #{name} #{version} from all mirrors")
  end

  defp remove_file(path) do
    if File.exists?(path), do: File.rm!(path)
  end

  defp extract_tarball!(tarball, target_dir) do
    tarball
    |> File.read!()
    |> :hex_tarball.unpack(:memory)
    |> case do
      {:ok, %{contents: contents}} -> write_contents!(contents, target_dir)
      {:error, reason} -> raise("hex_core failed to unpack #{tarball}: #{inspect(reason)}")
    end
  end

  defp write_contents!(contents, target_dir) do
    File.mkdir_p!(target_dir)

    Enum.each(contents, fn {path, content} ->
      path = path |> to_string() |> safe_relative_path!()
      output = Path.join(target_dir, path)
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, content)
    end)
  end

  defp safe_relative_path!(path) do
    parts = Path.split(path)

    if Path.type(path) != :relative or ".." in parts or parts == [] do
      raise("unsafe package path #{inspect(path)}")
    end

    Path.join(parts)
  end

  defp ok_entry(entry, target_dir, tarball, source, mirror) do
    language_counts = language_counts(target_dir)

    %{
      status: "ok",
      source: source,
      mirror: mirror,
      name: entry.name,
      version: entry.version,
      downloads: Map.get(entry, :downloads),
      html_url: Map.get(entry, :html_url),
      docs_html_url: Map.get(entry, :docs_html_url),
      package_api_url: Map.get(entry, :package_api_url),
      path: Path.relative_to_cwd(target_dir),
      tarball: Path.relative_to_cwd(tarball),
      has_elixir: has_elixir?(language_counts),
      language_counts: language_counts
    }
  end

  defp maybe_prune_non_elixir(entries, %{prune_non_elixir: true}) do
    Enum.map(entries, fn
      %{status: "ok", has_elixir: false, path: path} = entry ->
        File.rm_rf!(path)
        %{entry | status: "skipped", source: "pruned_non_elixir"}

      entry ->
        entry
    end)
  end

  defp maybe_prune_non_elixir(entries, _opts), do: entries

  defp has_elixir?(counts), do: Map.get(counts, "ex", 0) + Map.get(counts, "exs", 0) > 0

  defp language_counts(path) do
    path
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.reduce(%{}, fn file, acc ->
      ext = file |> Path.extname() |> String.trim_leading(".") |> normalize_ext()
      Map.update(acc, ext, 1, &(&1 + 1))
    end)
  end

  defp normalize_ext(""), do: "no_ext"
  defp normalize_ext(ext), do: ext
end
