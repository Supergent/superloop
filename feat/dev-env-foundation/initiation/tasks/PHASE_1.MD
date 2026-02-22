# PHASE 1: Superloop Baseline Stack

## P1.1 Workflow Hygiene

1. [x] Create dedicated worktree and branch: `feat/dev-env-foundation/initiation`.
2. [ ] Ensure issue metadata contains Feature Path, Branch, Scope, and Related PRs.
3. [ ] Open initiation PR with `PLAN.MD` and this phase file.

## P1.2 Superloop Local Stack

1. [x] Add root `.envrc`, `.envrc.example`, `devenv.nix`, and `devenv.yaml`.
2. [x] Add `scripts/dev-env-doctor.sh` and `scripts/dev-superloop-ui.sh`.
3. [x] Add stack documentation in `docs/dev-env-stack.md`.
4. [x] Add `.direnv/`, `.devenv/`, and `devenv.lock` ignores.

## P1.3 Target Bootstrap Profiles

1. [x] Add `scripts/dev-env/profiles/supergent/*` baseline files.
2. [x] Add `scripts/bootstrap-target-dev-env.sh`.
3. [x] Fix bootstrap repo validation to support git worktrees.

## P1.4 Docs and Port Contracts

1. [x] Align Superloop docs to named URL `superloop-ui.localhost:1355`.
2. [x] Update `packages/superloop-ui/src/cli.ts` to honor `PORT` defaulting behavior for wrappers/proxies.

## P1.5 Shared Skill Pack Alignment

1. [x] Add shared `local-dev-stack` skill with cross-runner local stack contract.
2. [x] Add shared `feature-initiation` skill with FIW/worktree protocol.
3. [x] Update `construct-superloop` to reference companion shared skills and local stack awareness.
4. [x] Update `superloop-view` examples to use env-driven named localhost URL.
5. [x] Upgrade `scripts/install-skill.sh` to sync selected/all shared skills to both Claude Code and Codex.

## P1.V Validation

1. [x] Run script lint/syntax checks for new shell scripts.
2. [x] Run minimal package checks for modified TypeScript/docs surfaces.
