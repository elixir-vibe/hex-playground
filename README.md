# Hex Playground

Corpus playground for running local tools against popular Hex.pm packages.

## Fetch the corpus

Fetch and extract the top 300 Hex packages by downloads:

```sh
cd ~/Development/hex-playground
./scripts/fetch_top_hex.exs --limit 300 --concurrency 8
```

This creates:

- `manifest.json` — package metadata, paths, downloads, file-extension counts
- `sources/<package>-<version>/` — extracted package sources
- `tarballs/<package>-<version>.tar` — cached Hex tarballs

The script uses the Hex.pm package API:

```text
https://hex.pm/api/packages?sort=downloads&page=N
```

and downloads release tarballs from:

```text
https://repo.hex.pm/tarballs/<name>-<version>.tar
```

It prefers `latest_stable_version` and falls back to `latest_version`.

## Corpus stats

```sh
./scripts/corpus_stats.exs
```

## Run tools against every package

Use `scripts/run_tool.exs` with a command after `--`. Placeholders:

- `{name}` — Hex package name
- `{version}` — package version
- `{path}` — relative source path
- `{abs_path}` — absolute source path

Examples:

```sh
./scripts/run_tool.exs --limit 20 -- elixir -e 'IO.puts(System.get_env("HEX_PLAYGROUND_PACKAGE"))'

./scripts/run_tool.exs --limit 300 -- bash -lc 'find lib src -type f 2>/dev/null | wc -l'

./scripts/run_tool.exs --limit 300 -- bash -lc 'mix ex_dna --format json 2>/dev/null || true'
```

Each run writes:

- `runs/<timestamp>/results.ndjson`
- `runs/<timestamp>/summary.json`
- one log file per package

## Notes

This directory is intentionally data-heavy. Keep generated corpus data out of git unless explicitly needed.
