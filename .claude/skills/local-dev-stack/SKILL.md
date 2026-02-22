---
name: local-dev-stack
description: |
  Shared local development environment contract for Superloop and target repos.
  Use when setting up local tooling, startup commands, or local URL contracts.
  Triggers: "devenv", "direnv", "portless", "local stack", "dev environment"
---

# Local Dev Stack

This skill is runner-agnostic and applies equally to Claude Code and Codex.

## Purpose

Keep local execution reproducible and stable across contributors and agents without coupling product behavior to one local setup.

## Baseline Contract

Use three layers by default:

1. `devenv` for reproducible tooling.
2. `direnv` for per-repo auto-loading.
3. `portless` for stable named `*.localhost` routes.

## Canonical Commands

When available in a repo, prefer these commands:

```bash
direnv allow
scripts/dev-env-doctor.sh
```

For Superloop UI lane:

```bash
scripts/dev-superloop-ui.sh
```

For target-repo lanes (when wrappers exist in that repo):

```bash
scripts/dev-<target>.sh
scripts/dev-<target>-verify.sh
```

## URL and Env Rules

Prefer env-driven URLs over hardcoded ports.

- Superloop UI (canonical): `SUPERLOOP_UI_BASE_URL` (default `http://superloop-ui.localhost:1355`)
- Superloop UI compatibility alias: `SUPERLOOP_UI_URL` (fallback only)
- Canonical app URL: `SUPERLOOP_DEV_BASE_URL` (profile default depends on target repo)
- Canonical verify URL: `SUPERLOOP_VERIFY_BASE_URL` (profile default depends on target repo)
- Canonical raw dev port (optional): `SUPERLOOP_DEV_PORT` (target-repo default often `5174`)

For repos still migrating, keep compatibility aliases as fallback only:

- `<TARGET>_BASE_URL` -> fallback alias for `SUPERLOOP_DEV_BASE_URL`
- `<TARGET>_VERIFY_BASE_URL` (or repo-specific equivalent) -> fallback alias for `SUPERLOOP_VERIFY_BASE_URL`
- `<TARGET>_DEV_PORT` -> fallback alias for `SUPERLOOP_DEV_PORT`

Resolution order should be:

1. Canonical `SUPERLOOP_*`
2. Product-specific alias
3. Generic env fallback (`TEST_BASE_URL`, `PORT`) where applicable
4. Explicit localhost fallback only for approved raw-runtime scripts

See `docs/dev-env-contract-v1.md` for the full contract.

## Target Adapter Readiness

For target repos adopting the contract, require:

1. Target adapter manifest at `.superloop/dev-env/adapter.manifest.json`.
2. Manifest mode declaration: `canonical_only` or `canonical_with_aliases`.
3. Evidence coverage for:
   - `script_resolution_proof`
   - `runbook_alignment_proof`
   - `guardrail_check_proof`

If a target has no active alias usage, set mode to `canonical_only` and keep this explicit in the manifest and runbook packet.

## Escape Hatches

The baseline must remain optional for compatibility and incident response.

- `USE_DEVENV=0` to bypass devenv activation.
- `PORTLESS=0` to bypass named proxy routing.
- `DIRENV_DISABLE=1` to disable direnv.

## Authoring Guidance

When generating specs, docs, or scripts:

- Prefer wrapper scripts over direct tool invocations.
- Prefer env vars over hardcoded localhost ports.
- Keep CI behavior independent of local stack requirements.
- Do not make acceptance criteria depend on `devenv`, `direnv`, or `portless` being mandatory.
