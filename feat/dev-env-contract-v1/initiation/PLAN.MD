# dev-env-contract-v1: Initiation Plan

## Goal

Define a Superloop-owned local execution environment contract for cross-repo orchestration, then wire constructor-facing guidance so both Claude Code and Codex consistently emit and consume that contract.

## Scope

- Define canonical variable names, precedence rules, and fallback policy for dev and lab execution URLs/ports.
- Update constructor/skill guidance to require the contract during loop construction.
- Provide target-repo adapter onboarding guidance for repos that currently use product-specific env keys.
- Add rollout guardrails to prevent new hardcoded localhost/port assumptions.

## Non-Goals (this iteration)

- Migrating every existing target repository in this single PR.
- Removing all legacy env aliases immediately.
- Changing hosted production runtime configuration.

## Primary References

- `handbook/features/INITIATION.MD`
- `.claude/skills/construct-superloop/SKILL.md`
- `.claude/skills/local-dev-stack/SKILL.md`
- `.claude/skills/feature-initiation/SKILL.md`
- `README.md`

## Architecture

1. Superloop defines canonical contract keys (`SUPERLOOP_DEV_BASE_URL`, `SUPERLOOP_LAB_BASE_URL`, optional `SUPERLOOP_DEV_PORT`) and precedence behavior.
2. `/construct-superloop` guidance treats these keys as orchestration-level inputs independent of target product naming.
3. Target repos consume the contract through adapter patches (dual-read canonical + legacy keys during migration).
4. Validation and rollout docs enforce one contract source and explicit exception handling for raw localhost tests.

## Decisions

- Namespace ownership follows orchestration ownership (`SUPERLOOP_*`) rather than any single target product.
- Constructor guidance remains runner-agnostic and explicitly applies to both Claude Code and Codex.
- Migration uses compatibility aliases first, then deprecates legacy prefixes after adoption criteria are met.

## Risks / Constraints

- Inconsistent env naming across target repos can cause silent run divergence.
- Overly aggressive enforcement can break legitimate raw-localhost diagnostic flows.
- Skill/docs drift can reintroduce contract ambiguity if not validated in rollout checks.

## Gate Baseline

- Tests mode: N/A (documentation/policy initiation)
- Tests commands: N/A for initiation packet
- Validation require on completion: N/A
- Validation checklist mapping file: N/A

## Phases

- **Phase 1**: Contract v1 specification and constructor skill alignment.
- **Phase 2**: Target-repo adapter onboarding kit and migration guidance.
- **Phase 3**: Enforcement guardrails, rollout sequencing, and deprecation policy.
