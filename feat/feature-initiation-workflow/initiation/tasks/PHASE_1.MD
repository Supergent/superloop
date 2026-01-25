# Phase 1 - Define Workflow, Templates, and Scaffolding

## P1.1 Canonical Workflow Documentation
1. [x] Create `handbook/features/INITIATION.MD` with Superloop-specific initiation workflow (branch, worktree, folder structure, issue discipline).
2. [x] Add `handbook/features/INITIATION.MD` reference in `README.md` (Contributor/Workflow section).

## P1.2 Templates for Initiation Artifacts
1. [x] Create `handbook/features/templates/PLAN.MD` template with goal, scope, decisions, risks, phases.
2. [x] Create `handbook/features/templates/PHASE_1.MD` template with atomic task numbering (P1.x) and validation section.

## P1.3 Optional Scaffolding Script
1. [x] Add `scripts/init-feature.sh` to scaffold `feat/<feature>/initiation` and copy templates.
2. [x] Script accepts feature name and optional slug (default `initiation`).
3. [x] Script prints issue checklist snippet (Feature Path, Branch, Scope links, Related PRs).

## P1.V Validation
1. [x] Run `scripts/init-feature.sh <feature-name>` and confirm files created in `feat/<feature-name>/initiation/`.
2. [x] Verify `README.md` links to `handbook/features/INITIATION.MD`.
