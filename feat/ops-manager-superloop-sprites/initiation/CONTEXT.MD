# Context: Ops Manager for Superloop + Sprites

## Problem Statement
Superloop already executes complex run lifecycles and emits rich local artifacts, but there is no external operations control-plane that treats each run as a first-class managed unit across isolated Sprite sandbox VMs.

Today this creates three operational gaps for the team dogfooding Supergent/Superloop:

1. Visibility gap:
- Operators can inspect a repo-local `.superloop/` tree, but cannot reliably aggregate run state from outside the runtime boundary.

2. Control gap:
- Intervention exists (`cancel`, approval decisions), but there is no explicit manager contract that can safely issue run control intents and reconcile outcomes.

3. Coordination gap:
- Sprite isolation gives deterministic execution, but there is no canonical mapping from sprite runtime signals to a manager lifecycle state machine.

## Why Loop Run Is Primary
`Loop Run` is the operational primitive that aligns with both technical and product goals:

- It maps directly to execution and outcomes that users care about (started, running, stuck, blocked, complete).
- It has stable artifact surfaces already emitted by Superloop (`events.jsonl`, `run-summary.json`, `state.json`, `active-run.json`).
- It remains composable: workspace/repo abstractions can be attached as dimensions without changing run-level control semantics.

## Runtime Boundaries

### Inside Sprite (Runtime Plane)
- Superloop orchestrates planner/implementer/tester/reviewer and writes canonical local artifacts.
- Runtime remains source of truth for role execution details.

### Outside Sprite (Ops Plane)
- Ops manager ingests snapshot + event envelopes.
- Ops manager computes lifecycle state and policy actions.
- Ops manager issues control intents (pause/cancel/approval decisions) through explicit interfaces.

### Contract Boundary
- V0 is pull-first: manager reads normalized outputs from adapter scripts.
- Streaming/service integrations are follow-on after contract stabilization.

## Primary Internal User Persona (Dogfood)
The first user persona is the internal Supergent/Superloop operator-builder:

- Runs many loop executions during active feature work.
- Needs deterministic isolation (one loop per sprite by default).
- Needs fast answers to: "what is running", "what is blocked", "what needs intervention", "what completed safely".

## Operator Journeys (V0)

### Journey 1: Observe Current Run
1. Operator selects loop id + runtime repo path.
2. Manager obtains a normalized snapshot.
3. Manager renders lifecycle state, gate posture, and current intervention requirements.

Success criteria:
- Snapshot resolves to one lifecycle state with no ambiguous status.
- Operator can identify latest run id and iteration.

### Journey 2: Stream New Events
1. Manager polls event envelopes with a cursor.
2. Cursor advances monotonically.
3. Manager updates lifecycle projection and activity feed.

Success criteria:
- No duplicated or skipped events under normal operation.
- Cursor mismatch/fork conditions fail closed and require explicit reset.

### Journey 3: Intervene Safely
1. Manager detects risk (stuck threshold, pending approval, runtime stop event).
2. Manager issues control intent through approved commands.
3. Manager verifies resulting runtime state via fresh snapshot/events.

Success criteria:
- Control intents are externally visible in runtime artifacts.
- Manager records outcome as an explicit transition, not implicit guesswork.

## Constraints and Assumptions
- Superloop artifact formats are authoritative and may evolve; adapter outputs must be versioned (`v1` now).
- V0 prioritizes deterministic behavior and debugging over maximum throughput.
- One loop per sprite is the default compute isolation policy.
- Multi-tenant security and billing are out of scope for initiation.

## Risks
- Artifact schema drift without envelope versioning can silently break ops state projection.
- Cursor handling errors can create visibility gaps (duplicate or dropped events).
- Manager policies can conflict with runtime recovery if control semantics are not clearly layered.

## Mitigations in This Iteration
- Contract schema for snapshot and event envelopes.
- Script adapters that fail closed on missing required artifacts.
- Explicit lifecycle mapping document to separate runtime facts from manager interpretation.
- Dogfood rollout stages with acceptance criteria and rollback behavior.
