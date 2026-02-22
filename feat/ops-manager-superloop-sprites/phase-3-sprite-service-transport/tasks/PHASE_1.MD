# Phase 1 - Sprite Service Transport + Manager Adapter

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-3-sprite-service-transport/PLAN.MD` aligns with prior phases and current repo state.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/43`).
3. [x] Link this phase packet from the issue and include prior PR context (`#40`, `#42`).

## P1.1 Sprite Service Endpoints
1. [x] Add sprite service handlers for:
   1. [x] `GET /ops/snapshot?loopId=<id>`
   2. [x] `GET /ops/events?loopId=<id>&cursor=<offset>&maxEvents=<n>`
   3. [x] `POST /ops/control` (`cancel|approve|reject`)
2. [x] Ensure endpoint responses preserve `schema/ops-manager.contract.schema.json` envelope shapes.
3. [x] Return structured transport errors with machine-readable codes.

## P1.2 Manager Transport Abstraction
1. [x] Add manager transport selector (`local` vs `sprite_service`) in reconcile/control flows.
2. [x] Add service client wrappers that normalize service responses into existing manager core pipeline.
3. [x] Keep local mode as fallback when service mode is unavailable.

## P1.3 Auth, Retry, and Idempotency
1. [x] Add service auth token validation for manager-to-sprite requests.
2. [x] Add retry/backoff policy for snapshot/event polling under transient failures.
3. [x] Add idempotency keys for control intents to prevent duplicate side effects.
4. [x] Persist transport attempt metadata in manager intent logs.

## P1.4 Docs and Runbook Updates
1. [x] Update `docs/ops-manager-v0.md` with service transport mode and endpoint contract usage.
2. [x] Update `docs/ops-manager-sprite-integration.md` with concrete service API mapping.
3. [x] Update `docs/ops-manager-runbook.md` with service outage fallback and retry procedures.

## P1.5 Test Coverage
1. [x] Add `tests/ops-manager-service.bats` for service transport success/failure paths.
2. [x] Add fixtures under `tests/fixtures/ops-manager/service/` for service response envelopes and error cases.
3. [x] Validate parity between local and service transports for projection/control outcomes.

## P1.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Updated docs reference real scripts/endpoints and fallback behavior.
