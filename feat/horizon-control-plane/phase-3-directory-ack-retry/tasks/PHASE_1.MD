# Phase 1 - Horizon Directory + Ack/Retry Baseline

## P1.0 Scope Discipline
1. [x] Keep phase scope additive and decoupled from Ops Manager runtime internals.
2. [x] Keep changes limited to Horizon scripts/contracts/docs/tests.

## P1.1 Directory Primitive
1. [x] Add `schema/horizon-directory.schema.json`.
2. [x] Add `docs/examples/horizon-directory.example.json`.
3. [x] Add `scripts/validate-horizon-directory.sh` with strict + non-strict validation paths.

## P1.2 Orchestrator Directory Integration
1. [x] Extend `scripts/horizon-orchestrate.sh` with `--directory-file` and `--directory-mode`.
2. [x] Support directory-driven adapter/target overrides with optional fallback behavior.
3. [x] Enforce required-mode fail-closed behavior for unknown recipients.

## P1.3 Ack + Retry Runtime
1. [x] Add `scripts/horizon-ack.sh` for deterministic receipt ingest and idempotent dedupe.
2. [x] Add `scripts/horizon-retry.sh` reconcile loop with timeout/backoff/retry budget controls.
3. [x] Persist ack/retry/dead-letter artifacts under `.superloop/horizons/`.

## P1.4 Tests
1. [x] Add `tests/horizon-directory.bats` for directory validator behavior.
2. [x] Add `tests/horizon-ack.bats` for ack transition + dedupe behavior.
3. [x] Add `tests/horizon-retry.bats` for retry + escalation/dead-letter behavior.
4. [x] Extend `tests/horizon-orchestrate.bats` for directory-mode behaviors.

## P1.5 Documentation
1. [x] Update `docs/horizon-planning.md` with Phase 3 contracts/commands/artifacts.
2. [x] Update `README.md` Horizon section with directory + ack/retry surfaces.

## P1.V Validation
1. [x] `bash -n scripts/horizon-orchestrate.sh scripts/horizon-ack.sh scripts/horizon-retry.sh scripts/validate-horizon-directory.sh` passes.
2. [x] `/usr/bin/bats tests/horizon-packet.bats tests/horizon-orchestrate.bats tests/horizon-directory.bats tests/horizon-ack.bats tests/horizon-retry.bats` passes.
