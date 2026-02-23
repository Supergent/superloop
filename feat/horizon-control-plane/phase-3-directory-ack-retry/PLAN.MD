# Feature: Horizon Control Plane (Phase 3 Directory + Ack/Retry)

## Goal
Add Horizon-native directory, delivery acknowledgment ingest, and bounded retry/dead-letter runtime primitives while preserving strict decoupling from Ops Manager internals.

## Scope
- Add optional Horizon directory contract (`.superloop/horizon-directory.json`) and schema validation tooling.
- Extend `scripts/horizon-orchestrate.sh` with directory-aware routing (`--directory-mode off|optional|required`, `--directory-file`).
- Add `scripts/horizon-ack.sh` for deterministic receipt ingest and `dispatched -> acknowledged|failed|escalated|cancelled` transitions.
- Add `scripts/horizon-retry.sh` reconcile loop for timed-out dispatched packets with retry/backoff limits and dead-letter escalation.
- Persist ack/retry artifacts and telemetry under `.superloop/horizons/`.
- Add BATS coverage for directory validation, directory routing, ack dedupe, and retry/escalation behavior.
- Update Horizon docs/readme with contracts, commands, and failure semantics.

## Non-Goals (this iteration)
- Any Ops Manager bridge ingestion logic or Ops runtime coupling.
- External transport plugins beyond `filesystem_outbox` and `stdout`.
- Autonomous execution side-effects outside Horizon packet state and telemetry artifacts.

## Primary References
- `feat/horizon-control-plane/phase-2-orchestrator-dispatch-adapters/PLAN.MD` - prior phase baseline.
- `scripts/horizon-orchestrate.sh` - dispatch planning/runtime surface.
- `scripts/horizon-packet.sh` - authoritative packet transition state machine.
- `docs/horizon-planning.md` - Horizon operating model.
- `README.md` - top-level operator quickstart.

## Architecture
Phase 3 introduces three additive planes:

1. Directory plane:
- Optional recipient contract (`horizon-directory`) for route + retry policy overrides.

2. Confirm plane:
- Receipt ingest command (`horizon-ack`) with idempotent dedupe and transition reconciliation.

3. Retry plane:
- Reconcile command (`horizon-retry`) for dispatched packet timeout evaluation, bounded retries, and dead-letter escalation.

All behavior remains repo-local and script-driven.

## Decisions
- Keep Horizon lane independent from Ops Manager bridge lane; shared integration happens only via stable dispatch envelopes.
- Keep directory optional by default (`optional` mode), with strict `required` mode for fail-closed recipient contract enforcement.
- Keep retry bounded and deterministic with explicit timeout, max retries, and backoff controls.
- Keep all new controls auditable through append-only telemetry files and explicit state artifacts.

## Risks / Constraints
- Concurrent script invocations are not lock-managed in this phase.
- Filesystem outbox remains a handoff contract, not guaranteed external delivery.
- Ack/retry state growth requires future retention policy once production volume increases.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `/usr/bin/bats tests/horizon-packet.bats tests/horizon-orchestrate.bats tests/horizon-directory.bats tests/horizon-ack.bats tests/horizon-retry.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Horizon packet lifecycle runtime.
- **Phase 2**: Orchestrator planning/dispatch adapters.
- **Phase 3**: Directory + ack/retry/dead-letter runtime and docs/tests.
