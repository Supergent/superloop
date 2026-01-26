# Feature: Superloop Feature Initiation Workflow

## Goal
Establish a canonical, repeatable feature initiation workflow for Superloop (branch + worktree + `feat/<feature>/<slug>` folder + PLAN/PHASE tasks + issue discipline), and provide lightweight templates/scaffolding to make it fast to adopt.

## Scope
- Document the initiation workflow in-repo, scoped to Superloop.
- Provide templates for `PLAN.MD` and `tasks/PHASE_*.MD` with atomic numbering conventions.
- Add an optional scaffolding script to create `feat/<feature>/initiation` structure and copy templates.
- Update top-level docs to point to the initiation workflow.

## Non-Goals (this iteration)
- CI enforcement of issue metadata or scope checks.
- Automated GitHub issue/PR creation.
- Changes to Superloop runtime/orchestration behavior.

## Primary References
- `README.md` (project entry point for contributors)
- `ARCHITECTURE.md` (context for planning practices)

## Architecture
- **Documentation-first workflow**: a canonical `handbook/features/INITIATION.MD` defines requirements and steps.
- **Templates**: reusable `PLAN.MD` and `PHASE_1.MD` templates stored under `handbook/features/templates/`.
- **Optional scaffolding**: `scripts/init-feature.sh` creates the `feat/<feature>/initiation` folder and copies templates.

## Decisions
- Mirror the Supergent initiation workflow structure inside Superloop for consistency.
- Keep scaffolding optional (docs remain the source of truth).
- Use `feat/<feature-name>/initiation` as the reserved first-pass slug.

## Risks / Constraints
- Git worktree creation may be environment-dependent; document the command and make it optional.
- Without CI enforcement, adoption relies on documentation and tooling.

## Phases
- **Phase 1**: Author workflow docs + templates + scaffolding script, update README.
- **Phase 2** (future): Add lightweight validation (pre-commit or CI) for initiation artifacts.
