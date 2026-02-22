# Dev Env Contract v1

This document defines the canonical local execution environment contract for Superloop orchestration across target repositories.

## Contract Owner

Superloop owns this contract. Target repositories implement adapters to consume it.

## Canonical Variables

- `SUPERLOOP_DEV_BASE_URL`
  - Purpose: canonical base URL for primary local app execution lane.
  - Example: `http://supergent.localhost:1355`
- `SUPERLOOP_LAB_BASE_URL`
  - Purpose: canonical base URL for lab/evidence verification lane.
  - Example: `http://lab.supergent.localhost:1355`
- `SUPERLOOP_DEV_PORT` (optional)
  - Purpose: canonical raw local development port when a script requires explicit port selection.
  - Example: `5174`

## Resolution Order

When reading dev/lab URL or port values in Superloop-aware scripts:

1. Canonical `SUPERLOOP_*` key.
2. Target-repo legacy/product-specific alias (for example `SUPERGENT_*`).
3. Generic fallback env where applicable (for example `TEST_BASE_URL`, `PORT`).
4. Explicit hardcoded localhost fallback only when policy permits.

## Compatibility Policy

- Migration is additive: target repos should dual-read canonical + legacy keys first.
- Legacy aliases remain supported until rollout criteria are met.
- Constructor and local-dev skills must treat `SUPERLOOP_*` keys as canonical during new loop construction.

## Allowed Localhost Exceptions

Hardcoded localhost fallbacks are allowed only for scripts that intentionally validate raw-port local runtime behavior.

## Constructor Implications

`/construct-superloop` guidance should:

1. Require canonical `SUPERLOOP_*` env contract awareness for target repos.
2. Require adapter notes when target repos still use legacy naming.
3. Keep runner parity across Claude Code and Codex.
