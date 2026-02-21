# Worktree Branch Lifecycle Governance (Superloop)

## Goal
Add a native Superloop lifecycle audit command that deterministically inspects branch/worktree lifecycle health for a feature namespace and supports strict fail-closed operation.

## Scope
- Add a CLI command: `superloop.sh lifecycle-audit`.
- Detect lifecycle failure classes for feature-prefixed branches/worktrees.
- Support strict mode threshold enforcement and optional JSON report output.
- Cover command behavior with BATS tests.
- Wire usage/help documentation for the new command.

## Non-Goals (this iteration)
- No Convex-backed lifecycle persistence.
- No multi-repo orchestrator service.
- No mutation/cleanup automation in this pass (audit-only).

## Primary References
- `src/00-header.sh`: usage surface
- `src/60-commands.sh`: command implementation and dispatch targets
- `src/99-main.sh`: CLI routing
- `scripts/build.sh`: generate `superloop.sh`
- `tests/superloop.bats`: command integration tests

## Architecture
- Implement `lifecycle_audit_cmd()` in `src/60-commands.sh`.
- Use local git topology + worktree metadata + optional `gh` PR lookup to compute lifecycle signals.
- Emit human-readable summary and optional JSON report.
- Enforce strict mode by threshold checks.

## Decisions
- Keep audit deterministic on local git facts; treat PR lookup failures as explicit `pr_lookup_unknown` signal.
- Support policy via inline CLI thresholds in this first pass (future: policy-file support).
- Ship as audit-only to avoid unintended destructive actions.

## Risks / Constraints
- `gh` availability/auth may vary across environments.
- Worktree state can change during audit on active repos.
- Windows support may need follow-up for shell tooling assumptions.

## Phases
- **Phase 1**: Command surface + core audit implementation + tests.
