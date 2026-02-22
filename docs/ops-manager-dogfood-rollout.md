# Ops Manager Dogfood Rollout Plan

## Audience
First adopter persona:
- internal Supergent/Superloop builders operating loop runs in Sprite sandboxes

## Stage 0: Contract Readiness
Goal:
- finalize `v1` envelope schema and adapter behavior

Acceptance criteria:
- snapshot and event adapters emit schema-consistent envelopes
- cursor behavior is monotonic and fail-closed
- required artifacts and failure modes are documented

Fallback:
- direct runtime inspection via `.superloop/` files and existing CLI commands

## Stage 1: Passive Visibility
Goal:
- ops manager reads snapshot + events and renders lifecycle without sending controls

Acceptance criteria:
- manager lifecycle projection matches runtime truth on sampled runs
- pending approval and terminal states are surfaced accurately
- divergence detection triggers on inconsistent signals

Fallback:
- disable event stream consumption and use snapshot-only mode

## Stage 2: Assisted Control
Goal:
- manager can issue controlled interventions with confirmation loop

Acceptance criteria:
- cancel and approval intents are reflected in runtime artifacts
- manager requires post-intent confirmation before marking success
- failed or ambiguous control attempts escalate to operator review

Fallback:
- revert control execution to manual CLI usage while keeping passive visibility

## Stage 3: Sprite Service Integration
Goal:
- bind manager ingestion to sprite service APIs while keeping contract invariant

Acceptance criteria:
- transport swap does not change envelope schema
- service path parity with pull path for lifecycle outcomes
- error budget and retry behavior defined for service outages

Fallback:
- return to pull-based adapters for impacted sprites

## Rollback Rules
Rollback is required when any of the following occurs:
- cursor regression causes ambiguous event ordering
- manager marks control success without runtime confirmation
- lifecycle projection disagrees with runtime artifacts beyond defined tolerance

Rollback behavior:
1. disable active control intents
2. continue passive snapshot visibility only
3. open incident note with artifact evidence and last known good cursor
