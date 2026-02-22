# Feature: Ops Manager for Superloop + Sprites

## Goal
Deliver a dogfooding-ready operations layer that can create, observe, and control `Loop Run` execution in Sprite Sandbox VMs with a stable event/state contract.

## Scope
- Define `Loop Run` as the primary managed unit, with explicit mapping hooks for workspace/repo entities later.
- Establish default compute isolation policy: one loop run per sprite VM (configurable in future phases).
- Add a normalized ops contract for snapshot + incremental event ingestion from Superloop runtime artifacts.
- Add initial control hooks and lifecycle semantics for run start, pause/cancel intent, and terminalization visibility.
- Document architecture and rollout path for first internal operators (Supergent/Superloop team).

## Non-Goals (this iteration)
- Multi-tenant auth, billing, and organizational access controls.
- Full production-grade distributed tracing stack (vendor lock-in decision deferred).
- Replacing Superloop's internal role loop logic.
- Automated multi-loop packing/scheduling optimization beyond the default one-loop-per-sprite policy.

## Primary References
- `superloop.sh` - runtime orchestration and artifact emission surfaces.
- `src/60-commands.sh` - command/module parity for core runtime behaviors.
- `schema/config.schema.json` - loop configuration contract and extension points.
- `docs/dev-env-contract-v1.md` - environment contract patterns relevant to manager/runtime boundaries.
- `handbook/features/INITIATION.MD` - required feature initiation process.

## Architecture
The architecture is split into three layers:

1. Runtime layer (inside sprite):
- Superloop executes role iterations and writes canonical artifacts/events.
- A lightweight adapter (script-first in v0) reads artifacts and emits normalized envelopes.

2. Ops manager layer (outside sprite):
- Maintains the authoritative lifecycle state machine per `Loop Run`.
- Ingests snapshot + delta events and computes run health, phase, and operator-facing status.
- Applies policy (timeouts, stuck detection, intervention thresholds) and issues control intents.

3. Transport/control boundary:
- Pull-based ingestion first (poll/cursor) to reduce coupling.
- Push/streaming path (sprite service APIs) staged for follow-on phases once contract stabilizes.

## Decisions
- Primary managed entity is `Loop Run` now; repo/workspace become associated dimensions.
- Default isolation is one loop per sprite for deterministic debugging and blast-radius control.
- Ops manager uses an outer lifecycle state machine and treats Superloop as managed runtime.
- Contract-first integration: snapshot + incremental event envelopes before deep runtime rewrites.
- Dogfooding is the first launch track and acceptance environment.

## Risks / Constraints
- Artifact schema drift can break ingestion unless versioned envelopes are enforced.
- Visibility can be partial if sprite-side adapters are not consistently deployed.
- Bidirectional control must avoid conflicting with in-runtime recovery logic.
- Over-instrumentation can add latency/noise; minimal required telemetry must be defined early.

## Gate Baseline
- Tests mode: `disabled` (initiation documentation phase only).
- Tests commands: `N/A`.
- Validation require on completion: `false` (for initiation packet).
- Validation checklist mapping file: `N/A`.

## Phases
- **Phase 1**: Finalize contracts, initiation docs, and v0 ingestion/control packet.
- **Phase 2**: Implement runtime adapters and manager state-machine core for loop lifecycle.
- **Phase 3**: Integrate sprite service interfaces for richer observability/control and dogfood hardening.
