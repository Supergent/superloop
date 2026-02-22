# Ops Manager + Sprite Integration Boundaries

## Default Isolation
V0 default:
- one loop run per sprite VM

Rationale:
- deterministic troubleshooting
- simpler blast-radius and lifecycle ownership
- cleaner event/cursor semantics per runtime

## Boundary Model

### Inside Sprite
- Superloop runtime executes loop logic.
- Runtime writes artifacts under `.superloop/`.
- Optional sprite-local service endpoint can expose adapter outputs.

### Outside Sprite (Ops Manager)
- Polls or receives adapter envelopes.
- Projects manager lifecycle state.
- Issues control intents through approved control path.

## Integration Paths

1. Pull path (V0 default)
- Manager invokes/read-accesses:
  - `scripts/ops-manager-loop-run-snapshot.sh`
  - `scripts/ops-manager-poll-events.sh`
- Works without dedicated runtime service.

2. Service path (follow-on)
- Sprite service wraps same adapter contract over HTTP.
- Manager consumes the same envelopes with transport abstraction.
- Implemented service endpoints:
  - `GET /ops/snapshot?loopId=<id>`
  - `GET /ops/events?loopId=<id>&cursor=<offset>&maxEvents=<n>`
  - `POST /ops/control`
    - body: `{loopId, intent, by?, note?, idempotencyKey?, noConfirm?}`

## Control Surface
Manager control intents should map to explicit runtime operations:

- `CANCEL_LOOP`
  - Current path: `superloop.sh cancel --repo <repo>`
  - Confirm by snapshot/event transition to non-running terminal/idle state.

- `APPROVE_PENDING`
  - Current path: `superloop.sh approve --repo <repo> --loop <id>`
  - Confirm by `approval_consumed` and/or `loop_complete` semantics.

- `REJECT_PENDING`
  - Current path: `superloop.sh approve --repo <repo> --loop <id> --reject`
  - Confirm by rejection event + continued run behavior.

## Security and Trust Assumptions (V0)
- Sprite runtime and manager are within trusted internal dogfood boundary.
- Control commands are allowlisted; no arbitrary shell command pass-through.
- Manager writes are intent-based and auditable.
- Full authn/authz model is deferred beyond initiation.
- Service transport requires a shared token (`Authorization: Bearer <token>` or `X-Ops-Token`).
- Control requests should include idempotency keys to prevent duplicate side effects.

## Transport Fallback
- Primary mode: `sprite_service`
- Fallback mode: `local`

Operational rule:
1. If service transport fails after retries, manager records failure and operators can switch to local mode:
   - `scripts/ops-manager-reconcile.sh --transport local ...`
   - `scripts/ops-manager-control.sh --transport local ...`
2. After service recovery, replay from cursor start or last stable offset and reconcile before re-enabling automated interventions.

## Total Visibility Mode (Future)
Minimum telemetry additions to approach full observability:
- periodic runtime heartbeat with process metadata
- explicit command invocation log for manager-issued actions
- envelope sequence ids for stronger ordering diagnostics
- optional trace ids spanning manager intent -> runtime effect
