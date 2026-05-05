#!/usr/bin/env elixir
Mix.install([{:jason, "~> 1.4"}])

defmodule HexPlayground.RunTool do
  def main(args) do
    {opts, command} = parse_args(args)
    manifest = opts.manifest |> File.read!() |> Jason.decode!()
    entries = manifest["entries"] |> Enum.filter(&(&1["status"] == "ok")) |> Enum.take(opts.limit)

    run_dir = Path.join(opts.runs, timestamp())
    File.mkdir_p!(run_dir)

    results_path = Path.join(run_dir, "results.ndjson")
    summary_path = Path.join(run_dir, "summary.json")

    results =
      entries
      |> Task.async_stream(&run_one(&1, command, run_dir, opts),
        max_concurrency: opts.concurrency,
        timeout: opts.timeout,
        ordered: false
      )
      |> Stream.map(fn
        {:ok, result} -> result
        {:exit, reason} -> %{status: "runner_error", error: inspect(reason)}
      end)
      |> Enum.map(fn result ->
        File.write!(results_path, Jason.encode_to_iodata!(result), [:append])
        File.write!(results_path, "\n", [:append])
        result
      end)

    summary = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      command: command,
      total: length(results),
      passed: Enum.count(results, &(&1[:exit_status] == 0)),
      failed: Enum.count(results, &((&1[:exit_status] || 1) != 0)),
      results_path: Path.relative_to_cwd(results_path)
    }

    File.write!(summary_path, Jason.encode_to_iodata!(summary, pretty: true))
    IO.puts("Wrote #{summary_path}")
  end

  defp parse_args(args) do
    {opts, command, invalid} =
      OptionParser.parse(args,
        strict: [
          manifest: :string,
          runs: :string,
          concurrency: :integer,
          timeout: :integer,
          limit: :integer
        ]
      )

    if invalid != [], do: raise("invalid options: #{inspect(invalid)}")
    if command == [], do: raise("usage: scripts/run_tool.exs [opts] -- command {path}")

    cwd = File.cwd!()

    parsed = %{
      manifest: expand_path(Keyword.get(opts, :manifest, "manifest.json"), cwd),
      runs: expand_path(Keyword.get(opts, :runs, "runs"), cwd),
      concurrency: Keyword.get(opts, :concurrency, 4),
      timeout: Keyword.get(opts, :timeout, 120_000),
      limit: Keyword.get(opts, :limit, 300)
    }

    {parsed, command}
  end

  defp run_one(entry, command, run_dir, opts) do
    started = System.monotonic_time()

    try do
      package_log = Path.join(run_dir, "#{entry["name"]}-#{entry["version"]}.log")
      interpolated = Enum.map(command, &interpolate(&1, entry))
      {cmd, args} = List.pop_at(interpolated, 0)

      {output, exit_status} =
        System.cmd(cmd, args,
          cd: entry["path"],
          stderr_to_stdout: true,
          env: [{"HEX_PLAYGROUND_PACKAGE", entry["name"]}, {"HEX_PLAYGROUND_VERSION", entry["version"]}]
        )

      File.write!(package_log, output)

      %{
        status: "ok",
        package: entry["name"],
        version: entry["version"],
        path: entry["path"],
        command: interpolated,
        exit_status: exit_status,
        duration_ms: duration_ms(started),
        log: Path.relative_to_cwd(package_log),
        output_tail: tail(output, 4000),
        timed_out: false
      }
    rescue
      error ->
        %{
          status: "error",
          package: entry["name"],
          version: entry["version"],
          path: entry["path"],
          command: command,
          exit_status: nil,
          duration_ms: duration_ms(started),
          error: Exception.message(error),
          timed_out: opts.timeout
        }
    end
  end

  defp interpolate(arg, entry) do
    arg
    |> String.replace("{name}", entry["name"])
    |> String.replace("{version}", entry["version"])
    |> String.replace("{path}", entry["path"])
    |> String.replace("{abs_path}", Path.expand(entry["path"]))
  end

  defp expand_path(path, root) do
    if Path.type(path) == :absolute, do: path, else: Path.expand(path, root)
  end

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.to_iso8601(:basic)
    |> String.replace(~r/[^0-9T]/, "")
  end

  defp duration_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp tail(output, max_bytes) when byte_size(output) <= max_bytes, do: output
  defp tail(output, max_bytes), do: binary_part(output, byte_size(output), -max_bytes)
end

HexPlayground.RunTool.main(System.argv())
