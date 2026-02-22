# Phase 1 - Ops Manager Contract + V0 Integration Packet

## P1.0 Initiation and Scope Baseline
1. [x] Confirm `feat/ops-manager-superloop-sprites/initiation/PLAN.MD` reflects final scope, non-goals, and rollout assumptions.
2. [x] Add `feat/ops-manager-superloop-sprites/initiation/CONTEXT.MD` with operator journeys, sprite runtime boundaries, and control-plane constraints.
3. [x] Open/attach the feature issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/39`).

## P1.1 Loop Run Contract Definition
1. [x] Add `schema/ops-manager.contract.schema.json` for:
   1. [x] Loop run snapshot envelope.
   2. [x] Incremental event envelope (with version and cursor fields).
   3. [x] Health and lifecycle status projection fields.
2. [x] Add contract notes to `docs/ops-manager-v0.md` covering compatibility/versioning rules.
3. [x] Add fixtures under `tests/fixtures/ops-manager/` for snapshot/event examples.

## P1.2 Runtime Artifact Ingestion Adapters
1. [x] Add `scripts/ops-manager-loop-run-snapshot.sh` to emit one normalized snapshot from Superloop artifacts.
2. [x] Add `scripts/ops-manager-poll-events.sh` to emit incremental NDJSON envelopes with cursor persistence.
3. [x] Ensure adapters fail closed on missing required artifacts and emit actionable errors.
4. [x] Document required runtime artifact inputs in `docs/ops-manager-v0.md`.

## P1.3 Outer Lifecycle State Machine Spec
1. [x] Add `docs/ops-manager-state-machine.md` with canonical states/events/guards/actions for loop-run management.
2. [x] Define state mapping from Superloop runtime signals to manager lifecycle states.
3. [x] Specify intervention transitions (pause intent, cancel intent, terminalization handling).

## P1.4 Sprite Integration Boundaries
1. [x] Add `docs/ops-manager-sprite-integration.md` covering:
   1. [x] One loop per sprite default policy and future override hooks.
   2. [x] Service/API integration points for observability and control.
   3. [x] Security boundary assumptions for manager-to-sprite commands.
2. [x] Capture minimum telemetry contract needed for "total visibility" mode.

## P1.5 Dogfood Rollout Plan
1. [x] Add `docs/ops-manager-dogfood-rollout.md` with staged adoption for Supergent/Superloop internal use.
2. [x] Define acceptance criteria per stage (visibility, control reliability, failure handling).
3. [x] Define rollback/fallback behavior when manager and runtime state disagree.

## P1.V Validation
1. [x] `bats tests/ops-manager-contract.bats` passes.
2. [x] All new docs cross-link correctly and reference real files/commands.
3. [x] `schema/ops-manager.contract.schema.json` validates provided fixtures.
4. [x] Initiation packet is reviewable without external context.
