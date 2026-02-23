# Phase 1 - Horizon Packet Runtime Baseline

## P1.0 Scope Discipline
1. [x] Keep phase scope additive and decoupled from ops-manager controllers.
2. [x] Keep changes limited to horizon packet runtime + docs + tests.

## P1.1 Runtime Script
1. [x] Add `scripts/horizon-packet.sh` with commands: `create`, `transition`, `show`, `list`.
2. [x] Persist packet artifacts to `.superloop/horizons/packets/<packet-id>.json`.
3. [x] Persist append-only telemetry to `.superloop/horizons/telemetry/packets.jsonl`.
4. [x] Enforce deterministic status transitions and fail closed on invalid transitions.

## P1.2 Contract Fields
1. [x] Include `traceId`, `horizonRef`, `evidenceRefs`, and optional `loopId` in packet artifacts.
2. [x] Support repeated `--evidence-ref` on create/transition operations.
3. [x] Ensure list/show surfaces preserve artifact fidelity.

## P1.3 Tests
1. [x] Add `tests/horizon-packet.bats` for create + telemetry baseline.
2. [x] Add transition lifecycle success/failure coverage.
3. [x] Add list filter and missing-packet error coverage.

## P1.4 Documentation
1. [x] Update `docs/horizon-planning.md` with packet runtime usage and status model.
2. [x] Update `README.md` Horizon section with quick packet examples.

## P1.V Validation
1. [x] `bash -n scripts/horizon-packet.sh` passes.
2. [x] `/usr/bin/bats tests/horizon-packet.bats` passes.
