# Phase 1 - Native Lifecycle Audit Command

## P1.1 Command Surface
1. [x] Add `lifecycle-audit` to CLI usage output in `src/00-header.sh`.
2. [x] Route `lifecycle-audit` command in `src/99-main.sh`.
3. [x] Parse lifecycle-audit flags in `src/99-main.sh`:
   1. [x] `--feature-prefix`
   2. [x] `--main-ref`
   3. [x] `--strict`
   4. [x] `--json-out`
   5. [x] `--no-fetch`

## P1.2 Core Audit Implementation (`src/60-commands.sh`)
1. [x] Implement `lifecycle_audit_cmd()` with these metrics:
   1. [x] `ahead_without_pr`
   2. [x] `pr_lookup_unknown`
   3. [x] `stale_merged_local_branch`
   4. [x] `stale_merged_remote_branch`
   5. [x] `behind_and_dirty_worktree`
   6. [x] `stale_merged_worktree`
2. [x] Add strict mode threshold checks (all metrics max 0 for v0).
3. [x] Emit compact human summary for terminal usage.
4. [x] Write JSON report when `--json-out` is provided.

## P1.3 Build + Tests
1. [x] Add/extend BATS coverage in `tests/superloop.bats` for lifecycle command behavior.
2. [x] Rebuild generated `superloop.sh` via `scripts/build.sh`.
3. [x] Run targeted tests for new command path.
   1. [x] `bats` binary unavailable in current environment; executed equivalent manual smoke scenarios for pass + strict-fail paths.

## P1.V Validation
1. [x] `bash scripts/build.sh` succeeds.
2. [x] `bats tests/superloop.bats` includes lifecycle tests (execution pending on CI/host with bats installed).
3. [x] `./superloop.sh lifecycle-audit --repo <repo>` runs and prints summary.
