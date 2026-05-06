# Hex Playground

Corpus playground for running local tools against large sets of Hex.pm packages.

## Setup

```sh
cd ~/Development/hex-playground
mix deps.get
```

You can run it as a Mix task:

```sh
mix hex_playground.fetch --mode latest --limit 300 --concurrency 8
```

Or build a standalone escript:

```sh
mix escript.build
./hex_playground fetch --mode latest --limit 300
```

## Fetch a corpus

Fetch and extract the latest release of packages from the signed Hex repository
registry:

```sh
mix hex_playground.fetch --mode latest --limit 300 --concurrency 8
```

This creates:

- `manifest.json` — package metadata, paths, mirror used, and file-extension counts
- `sources/<package>-<version>/` — extracted package sources
- `tarballs/<package>-<version>.tar` — cached Hex tarballs

Useful modes:

```sh
# Latest release of every public Hex package
mix hex_playground.fetch --mode latest --concurrency 16 --prune-non-elixir

# Every public package version. Large: currently ~150k releases.
mix hex_playground.fetch --mode all --concurrency 16

# Top packages by downloads, using the Hex HTTP API for ranking
mix hex_playground.fetch --mode top --limit 1000 --concurrency 16
```

`latest` and `all` use the Hex repository endpoint:

```text
https://repo.hex.pm/versions
```

Tarballs are downloaded from:

```text
https://repo.hex.pm/tarballs/<name>-<version>.tar
```

and unpacked with `hex_core`.

## Mirror balancing

Tarball downloads can be balanced across multiple repository mirrors. Registry
discovery still uses `--registry-url` so the signed Hex.pm registry remains the
source of truth.

```sh
mix hex_playground.fetch \
  --mode latest \
  --limit 1000 \
  --concurrency 16 \
  --mirror https://repo.hex.pm \
  --mirror https://cdn.jsdelivr.net/hex \
  --mirror-strategy round_robin
```

You can also pass mirrors comma-separated:

```sh
mix hex_playground.fetch \
  --mirror https://repo.hex.pm,https://cdn.jsdelivr.net/hex \
  --mirror-strategy random
```

Available strategies:

- `round_robin` — distribute package tarball attempts across mirrors
- `random` — pick a random starting mirror per package

If a mirror fails for a tarball, the downloader falls back to the remaining
mirrors. Only `https://repo.hex.pm` is the official Hex.pm mirror; other mirrors
are useful for public tarballs but should be treated as untrusted.

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
