# Local Dev Stack: devenv + direnv + portless

This repo's local development baseline uses three layers:

1. `devenv` for reproducible tooling.
2. `direnv` for per-repo environment loading.
3. `portless` for stable named localhost routes.

## Quick Start

```bash
# one-time
direnv allow

# optional, explicit shell entry
devenv shell

# verify toolchain/scripts
scripts/dev-env-doctor.sh

# run the Superloop UI dashboard lane
scripts/dev-superloop-ui.sh
```

Default URL:

- `http://superloop-ui.localhost:1355/liquid`

## Escape Hatches

- `USE_DEVENV=0` disables devenv activation in `.envrc`.
- `PORTLESS=0` runs raw localhost without proxy.
- `DIRENV_DISABLE=1` disables direnv entirely.

## Target Repo Bootstrapping

Use the helper to apply the same baseline to target repos:

```bash
scripts/bootstrap-target-dev-env.sh --repo /path/to/repo --profile supergent
```

`--repo` accepts both normal git checkouts and git worktree paths.

Pass `--force` to overwrite existing stack files.
