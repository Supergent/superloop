# Feature: Ops Manager for Superloop + Sprites (Phase 2 Manager Core)

## Goal
Implement an executable ops-manager core that projects loop-run lifecycle from contract envelopes and executes confirmed control intents against Superloop runtimes.

## Scope
- Build manager state projection and reconciliation from `loop_run_snapshot` + `loop_run_event` envelopes.
- Add control-intent bridge for `cancel`, `approve`, and `reject` with explicit confirmation checks.
- Add divergence detection and escalation output when runtime signals conflict.
- Add BATS tests covering transitions, cursor behavior, control confirmation, and divergence handling.

## Non-Goals (this iteration)
- Sprite service/API transport layer (HTTP endpoints) beyond pull-based adapters.
- Multi-tenant authn/authz and billing.
- Multi-loop packing/scheduling policy changes (keep one-loop-per-sprite default).

## Primary References
- `feat/ops-manager-superloop-sprites/initiation/PLAN.MD` - initiation decisions and scope baseline.
- `feat/ops-manager-superloop-sprites/initiation/CONTEXT.MD` - operator journeys and boundary assumptions.
- `schema/ops-manager.contract.schema.json` - envelope contract source of truth.
- `scripts/ops-manager-loop-run-snapshot.sh` - runtime snapshot adapter.
- `scripts/ops-manager-poll-events.sh` - runtime event polling adapter.
- `docs/ops-manager-state-machine.md` - canonical lifecycle mapping.
- `src/60-commands.sh` - Superloop control operations (`cancel`, `approve`) and runtime behavior.

## Architecture
Phase 2 adds an executable manager core layer (script-first):

1. Projection engine:
- Ingest snapshot + incremental events.
- Compute canonical manager lifecycle state and confidence flags.
- Persist manager state for operator/automation consumers.

2. Control-intent bridge:
- Accept intent (`cancel`, `approve`, `reject`) via strict allowlist.
- Execute corresponding Superloop CLI action.
- Require post-intent confirmation before marking success.

3. Reconciliation loop:
- Compare projected state against fresh runtime snapshot.
- Detect divergence and emit escalation records with evidence pointers.

## Decisions
- Keep manager core in bash+jq for parity with existing Superloop runtime tooling.
- Maintain contract-first boundary; no direct parsing of role prompt logs.
- Treat control outcomes as transitions requiring confirmation evidence, not immediate success.
- Persist manager cursor/state in deterministic JSON files per loop for recoverability.

## Risks / Constraints
- Complex transition logic may drift from state-machine doc without test fixtures.
- Control confirmation windows can produce false negatives under delayed artifact writes.
- Divergence heuristics may be noisy until dogfood tuning stabilizes thresholds.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS suite)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Implement manager core scripts, state/cursor persistence, control confirmation, and tests.
- **Phase 2**: Harden dogfood operations and prep service/API transport integration.
