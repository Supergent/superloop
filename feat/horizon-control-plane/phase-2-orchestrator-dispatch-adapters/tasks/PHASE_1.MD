# Phase 1 - Horizon Orchestrator Dispatch Baseline

## P1.0 Scope Discipline
1. [x] Keep phase scope additive and decoupled from `superloop.sh run` and Ops Manager internals.
2. [x] Keep changes limited to Horizon orchestrator runtime + packet contract patch + docs + tests.

## P1.1 Orchestrator Runtime
1. [x] Add `scripts/horizon-orchestrate.sh` with commands: `plan`, `dispatch`.
2. [x] Add deterministic queued packet selection with sort order and optional filters (`--horizon-ref`, `--recipient-type`, `--limit`).
3. [x] Add freshness gating from packet TTL and created timestamp with explicit reason codes.
4. [x] Add adapter routing with `filesystem_outbox` (default) and `stdout`.
5. [x] Persist orchestrator run telemetry to `.superloop/horizons/telemetry/orchestrator.jsonl`.

## P1.2 Packet Contract Alignment
1. [x] Add `--loop-id` support in `scripts/horizon-packet.sh create` to align runtime behavior with documented contract.
2. [x] Keep packet state transitions fail-closed by reusing `horizon-packet.sh` transition command from orchestrator.
3. [x] Keep seam fields additive and nullable.

## P1.3 Tests
1. [x] Add `tests/horizon-orchestrate.bats` coverage for plan output + stale packet blocking.
2. [x] Add dispatch coverage for filesystem outbox adapter + packet transition behavior.
3. [x] Add dry-run, filter, and limit behavior coverage.
4. [x] Extend packet tests for new `--loop-id` contract field.

## P1.4 Documentation
1. [x] Update `docs/horizon-planning.md` with Phase 2 orchestrator contract, commands, adapters, and artifacts.
2. [x] Update `README.md` Horizon section with orchestrator quick examples and artifact notes.

## P1.V Validation
1. [x] `bash -n scripts/horizon-packet.sh scripts/horizon-orchestrate.sh` passes.
2. [x] `/usr/bin/bats tests/horizon-packet.bats tests/horizon-orchestrate.bats` passes.
