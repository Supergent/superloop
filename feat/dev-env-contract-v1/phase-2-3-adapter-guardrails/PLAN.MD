# dev-env-contract-v1: Phase 2-3 Adapter Kit + Guardrails

## Goal

Complete phase-2/phase-3 rollout for the Superloop dev env contract by shipping target adapter onboarding artifacts, constructor readiness requirements, and enforceable core decoupling guardrails.

## Scope

- Add target adapter manifest contract documentation and schema.
- Add constructor readiness/evidence requirements for adapter adoption.
- Add rollout + deprecation policy guidance.
- Enforce core-path decoupling in CI.

## Non-Goals

- Full migration of every external target repo in this change.
- Removing legacy aliases in all targets immediately.

## References

- `feat/dev-env-contract-v1/initiation/PLAN.MD`
- `docs/dev-env-contract-v1.md`
- `.claude/skills/construct-superloop/SKILL.md`
- `.claude/skills/local-dev-stack/SKILL.md`
- `scripts/check-core-decoupling.sh`
- `.github/workflows/ci.yml`

## Phases

- Phase 2: Adapter manifest + constructor readiness contract.
- Phase 3: CI enforcement + rollout/deprecation policy.
