# Phase 1 - Manager Core Runtime + Control Bridge

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-2-manager-core/PLAN.MD` aligns with initiation decisions and current repo state.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/41`).
3. [x] Link this phase packet from the issue and include initiation PR context (`#40`).

## P1.1 Lifecycle Projection Engine
1. [x] Add `scripts/ops-manager-project-state.sh` to compute manager lifecycle state from:
   1. [x] `loop_run_snapshot` envelope input.
   2. [x] Incremental `loop_run_event` envelope stream.
2. [x] Persist projected manager state to `.superloop/ops-manager/<loop>/state.json` (repo-local deterministic path).
3. [x] Include transition metadata in projected state:
   1. [x] previous_state
   2. [x] triggering_signal
   3. [x] current_state
   4. [x] confidence and divergence flags

## P1.2 Reconciliation and Divergence Handling
1. [x] Add `scripts/ops-manager-reconcile.sh` to merge fresh snapshot + recent events into a canonical manager view.
2. [x] Implement divergence detection rules aligned to `docs/ops-manager-state-machine.md`:
   1. [x] active-state mismatch vs incoming events
   2. [x] approval pending vs completion conflict
   3. [x] cursor regression or replay anomaly
3. [x] Emit escalation artifact `.superloop/ops-manager/<loop>/escalations.jsonl` with evidence pointers.

## P1.3 Control Intent Bridge
1. [x] Add `scripts/ops-manager-control.sh` with allowlisted intents:
   1. [x] `cancel` -> `superloop.sh cancel --repo <repo>`
   2. [x] `approve` -> `superloop.sh approve --repo <repo> --loop <id>`
   3. [x] `reject` -> `superloop.sh approve --repo <repo> --loop <id> --reject`
2. [x] Add confirmation logic `scripts/ops-manager-confirm-intent.sh`:
   1. [x] verify expected runtime artifact/event transitions
   2. [x] mark intent as succeeded/failed/ambiguous with timestamps
3. [x] Persist intent log to `.superloop/ops-manager/<loop>/intents.jsonl`.

## P1.4 Docs and Contract Tightening
1. [x] Update `docs/ops-manager-v0.md` with manager core execution flow and persisted state paths.
2. [x] Update `docs/ops-manager-state-machine.md` with explicit transition truth-table used by projection script.
3. [x] Add `docs/ops-manager-runbook.md` with operator procedures for:
   1. [x] stuck/divergence triage
   2. [x] safe control-intent retries
   3. [x] cursor reset and replay

## P1.5 Test Coverage
1. [x] Add `tests/ops-manager-core.bats` for projection, reconciliation, and control bridge behaviors.
2. [x] Add fixtures under `tests/fixtures/ops-manager/core/` for normal and divergent runtime cases.
3. [x] Ensure tests cover fail-closed behavior for invalid/missing envelopes and cursor anomalies.

## P1.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats` passes.
2. [x] All new scripts pass `bash -n` syntax checks.
3. [x] Updated docs reference real scripts, artifacts, and commands.
