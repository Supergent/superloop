# Dev Env Contract v1

This document defines the canonical local execution environment contract for Superloop orchestration across target repositories.

Related references:

- `docs/dev-env-target-adapter.md`
- `docs/dev-env-rollout-v1.md`
- `schema/dev-env-target-adapter.schema.json`

## Contract Owner

Superloop owns this contract. Target repositories implement adapters to consume it.

## Canonical Variables

- `SUPERLOOP_DEV_BASE_URL`
  - Purpose: canonical base URL for primary local app execution lane.
  - Example: `http://app.target.localhost:1355`
- `SUPERLOOP_VERIFY_BASE_URL`
  - Purpose: canonical base URL for verification/evidence lane.
  - Example: `http://verify.target.localhost:1355`
- `SUPERLOOP_DEV_PORT` (optional)
  - Purpose: canonical raw local development port when a script requires explicit port selection.
  - Example: `5174`

## Resolution Order

When reading dev/verify URL or port values in Superloop-aware scripts:

1. Canonical `SUPERLOOP_*` key.
2. Target-repo legacy/product-specific alias (if present).
3. Generic fallback env where applicable (for example `TEST_BASE_URL`, `PORT`).
4. Explicit hardcoded localhost fallback only when policy permits.

## Compatibility Policy

- Migration is additive: target repos should dual-read canonical + legacy keys first.
- Legacy aliases remain supported until rollout criteria are met.
- Constructor and local-dev skills must treat `SUPERLOOP_*` keys as canonical during new loop construction.

## Target Adapter Manifest

Target repositories adopt this contract through an adapter manifest:

- Canonical runtime path: `.superloop/dev-env/adapter.manifest.json`
- Schema: `schema/dev-env-target-adapter.schema.json`
- Authoring guide: `docs/dev-env-target-adapter.md`

Manifest mode options:

1. `canonical_only`
2. `canonical_with_aliases`

## Required Readiness Evidence

Each target adoption must plan and capture these artifacts:

1. `script_resolution_proof`
2. `runbook_alignment_proof`
3. `guardrail_check_proof`

See `docs/dev-env-target-adapter.md` for definitions and expected packet contents.

## Rollout And Deprecation

Wave sequencing, entry/exit criteria, failure handling, and alias-removal policy live in:

- `docs/dev-env-rollout-v1.md`

## Allowed Localhost Exceptions

Hardcoded localhost fallbacks are allowed only for scripts that intentionally validate raw-port local runtime behavior.

## Constructor Implications

`/construct-superloop` guidance should:

1. Require canonical `SUPERLOOP_*` env contract awareness for target repos.
2. Require a target adapter manifest path and mapping mode (or an explicit follow-on task to create it).
3. Require readiness evidence planning for script, runbook, and guardrail proofs.
4. Keep runner parity across Claude Code and Codex.
