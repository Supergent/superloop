# PHASE 1: Core Contract And Skill Alignment

## P1.1 Canonical Contract

1. [x] Add `docs/dev-env-contract-v1.md`.
2. [x] Define canonical keys: `SUPERLOOP_DEV_BASE_URL`, `SUPERLOOP_VERIFY_BASE_URL`, `SUPERLOOP_DEV_PORT`.
3. [x] Document fallback policy and localhost exception boundaries.

## P1.2 Skill Updates

1. [x] Update `.claude/skills/construct-superloop/SKILL.md` with canonical contract expectations.
2. [x] Update `.claude/skills/local-dev-stack/SKILL.md` to remove product-specific coupling in core guidance.

## P1.3 Core Decoupling

1. [x] Remove product-coupled examples from core README/config snippets.
2. [x] Make bootstrap profile listing dynamic (no hardcoded product profile in usage text).
3. [x] Add `scripts/check-core-decoupling.sh` and verify it passes.

## P1.4 Adapter Profile Alignment

1. [x] Update `scripts/dev-env/profiles/supergent/*` to export canonical keys first with compatibility aliases.

## P1.V Validation

1. [x] Run shell syntax checks for updated scripts.
2. [x] Run `scripts/check-core-decoupling.sh`.
3. [x] Run grep sanity checks for canonical key usage in updated core files.
