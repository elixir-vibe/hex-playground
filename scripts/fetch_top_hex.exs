#!/usr/bin/env elixir
Mix.install([{:jason, "~> 1.4"}, {:hex_core, "~> 0.15"}])

defmodule HexPlayground.FetchTopHex do
  @hex_api "https://hex.pm/api/packages"
  @repo_tarballs "https://repo.hex.pm/tarballs"

  def main(args) do
    opts = parse_args(args)
    File.mkdir_p!(opts.out)
    File.mkdir_p!(opts.tarballs)
    File.mkdir_p!(opts.tmp)

    packages = fetch_top_packages(opts.limit)

    manifest_entries =
      packages
      |> Task.async_stream(&fetch_package(&1, opts),
        max_concurrency: opts.concurrency,
        timeout: opts.timeout,
        ordered: true
      )
      |> Enum.map(fn
        {:ok, entry} -> entry
        {:exit, reason} -> %{status: "error", error: inspect(reason)}
      end)

    manifest = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      limit: opts.limit,
      count: Enum.count(manifest_entries, &(&1[:status] == "ok")),
      entries: manifest_entries
    }

    manifest_path = Path.join(opts.root, "manifest.json")
    File.write!(manifest_path, Jason.encode_to_iodata!(manifest, pretty: true))
    IO.puts("Wrote #{manifest_path}")
  end

  defp parse_args(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          limit: :integer,
          out: :string,
          tarballs: :string,
          tmp: :string,
          concurrency: :integer,
          timeout: :integer,
          force: :boolean,
          backend: :string
        ]
      )

    if invalid != [], do: raise("invalid options: #{inspect(invalid)}")

    root = File.cwd!()

    %{
      root: root,
      limit: Keyword.get(opts, :limit, 300),
      out: expand_path(Keyword.get(opts, :out, "sources"), root),
      tarballs: expand_path(Keyword.get(opts, :tarballs, "tarballs"), root),
      tmp: expand_path(Keyword.get(opts, :tmp, "tmp"), root),
      concurrency: Keyword.get(opts, :concurrency, 8),
      timeout: Keyword.get(opts, :timeout, 120_000),
      force: Keyword.get(opts, :force, false),
      backend: Keyword.get(opts, :backend, "hex_core")
    }
  end

  defp expand_path(path, root) do
    if Path.type(path) == :absolute, do: path, else: Path.expand(path, root)
  end

  defp fetch_top_packages(limit) do
    Stream.iterate(1, &(&1 + 1))
    |> Enum.reduce_while([], fn page, acc ->
      batch = get_json("#{@hex_api}?sort=downloads&page=#{page}")
      next = acc ++ batch

      cond do
        length(next) >= limit -> {:halt, Enum.take(next, limit)}
        batch == [] -> {:halt, next}
        true -> {:cont, next}
      end
    end)
  end

  defp fetch_package(pkg, opts) do
    name = pkg["name"]
    version = pkg["latest_stable_version"] || pkg["latest_version"]
    slug = "#{name}-#{version}"
    target_dir = Path.join(opts.out, slug)
    tarball = Path.join(opts.tarballs, "#{slug}.tar")

    if File.dir?(target_dir) and not opts.force do
      ok_entry(pkg, version, target_dir, tarball, "cached")
    else
      File.rm_rf!(target_dir)
      download_tarball!(name, version, tarball)
      extract_tarball!(tarball, target_dir, opts.tmp, slug, opts.backend)
      ok_entry(pkg, version, target_dir, tarball, "fetched")
    end
  rescue
    error ->
      %{
        status: "error",
        name: pkg["name"],
        version: pkg["latest_stable_version"] || pkg["latest_version"],
        error: Exception.message(error)
      }
  end

  defp ok_entry(pkg, version, target_dir, tarball, source) do
    %{
      status: "ok",
      source: source,
      name: pkg["name"],
      version: version,
      downloads: pkg["downloads"],
      html_url: pkg["html_url"],
      docs_html_url: pkg["docs_html_url"],
      package_api_url: pkg["url"],
      path: Path.relative_to_cwd(target_dir),
      tarball: Path.relative_to_cwd(tarball),
      language_counts: language_counts(target_dir)
    }
  end

  defp download_tarball!(name, version, tarball) do
    if File.exists?(tarball), do: File.rm!(tarball)
    url = "#{@repo_tarballs}/#{name}-#{version}.tar"
    IO.puts("Downloading #{name} #{version}")
    run!("curl", ["-fL", "--retry", "3", "--retry-delay", "1", "-o", tarball, url])
  end

  defp extract_tarball!(tarball, target_dir, _tmp_root, _slug, "hex_core") do
    tarball
    |> File.read!()
    |> :hex_tarball.unpack(:memory)
    |> case do
      {:ok, %{contents: contents}} -> write_contents!(contents, target_dir)
      {:error, reason} -> raise("hex_core failed to unpack #{tarball}: #{inspect(reason)}")
    end
  end

  defp extract_tarball!(tarball, target_dir, tmp_root, slug, "tar") do
    tmp_dir = Path.join(tmp_root, slug)
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    File.mkdir_p!(target_dir)

    run!("tar", ["-xf", tarball, "-C", tmp_dir])

    contents = Path.join(tmp_dir, "contents.tar.gz")

    if File.exists?(contents) do
      run!("tar", ["-xzf", contents, "-C", target_dir])
    else
      run!("tar", ["-xf", tarball, "-C", target_dir])
    end

    File.rm_rf!(tmp_dir)
  end

  defp extract_tarball!(_tarball, _target_dir, _tmp_root, _slug, backend) do
    raise("unknown backend #{inspect(backend)}; expected hex_core or tar")
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

  defp get_json(url) do
    {body, 0} = run("curl", ["-fsSL", url])
    Jason.decode!(body)
  end

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

  defp run!(cmd, args) do
    case run(cmd, args) do
      {_output, 0} -> :ok
      {output, status} -> raise("#{cmd} #{Enum.join(args, " ")} failed with #{status}: #{output}")
    end
  end

  defp run(cmd, args) do
    System.cmd(cmd, args, stderr_to_stdout: true)
  end
end

HexPlayground.FetchTopHex.main(System.argv())
