# Dev Env Target Adapter Contract

This document defines how target repositories declare adoption of the canonical Superloop local env contract.

## Purpose

Keep Superloop core target-agnostic while allowing each target repository to map canonical keys to local conventions safely.

## Manifest Schema

- Schema file: `schema/dev-env-target-adapter.schema.json`
- Version: `v1`

The manifest should live inside the target repo at:

- `.superloop/dev-env/adapter.manifest.json`

## Required Fields

1. `target.id` and `target.repoPath`
2. Canonical contract keys:
   - `SUPERLOOP_DEV_BASE_URL`
   - `SUPERLOOP_VERIFY_BASE_URL`
   - `SUPERLOOP_DEV_PORT`
3. Mapping mode:
   - `canonical_only`
   - `canonical_with_aliases`
4. Required evidence artifacts list

## Mapping Modes

1. `canonical_only`
   - Use only canonical keys.
   - Missing canonical keys should fail fast with explicit errors.
2. `canonical_with_aliases`
   - Resolve canonical keys first.
   - Resolve target-repo aliases second.
   - Keep explicit fallback behavior documented.

## Required Readiness Evidence

Each target adoption should include evidence proving:

1. `script_resolution_proof`
   - dev and verification scripts resolve canonical keys first.
2. `runbook_alignment_proof`
   - runbooks and gate docs match script resolution order.
3. `guardrail_check_proof`
   - hardcoding/decoupling checks pass.

## Constructor Requirements

`/construct-superloop` should require the adapter manifest (or create-task for it) before treating target-repo local execution as contract-ready.

Minimum constructor outputs for target readiness:

1. Manifest path.
2. Mapping mode.
3. Evidence artifact plan for the three required proofs.
4. Explicit note when aliases are not used (`canonical_only` mode).

## Examples

- Canonical-only example: `docs/examples/dev-env-target-adapter.canonical.json`
- Alias-compatible example: `docs/examples/dev-env-target-adapter.aliases.json`
