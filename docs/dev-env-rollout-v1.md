# Dev Env Contract Rollout v1

This document defines rollout and deprecation policy for adopting the canonical Superloop local env contract across target repositories.

## Rollout Waves

1. Wave 1: Supergent pilot
   - entry: canonical keys available and adapter manifest committed.
   - exit: required evidence artifacts complete and stable.
2. Wave 2: one non-Supergent target
   - entry: Wave 1 exit met and constructor guidance updated.
   - exit: successful canonical or alias mode adoption in external target.
3. Wave 3: remaining prioritized target repos
   - entry: Wave 2 exit met.
   - exit: all active targets declare mapping mode and pass guardrails.

## Entry Criteria (Per Target)

1. `.superloop/dev-env/adapter.manifest.json` exists and validates against `schema/dev-env-target-adapter.schema.json`.
2. Target scripts resolve canonical contract keys first.
3. Evidence plan includes required artifacts.

## Exit Criteria (Per Target)

1. `script_resolution_proof` captured.
2. `runbook_alignment_proof` captured.
3. `guardrail_check_proof` captured.
4. No unresolved contract drift findings.

## Failure Handling

If adoption fails:

1. Keep target on current mapping mode.
2. Revert only adapter-layer changes for the target.
3. Preserve canonical contract in Superloop core (do not rollback core naming).

## Alias Deprecation Policy

Legacy aliases can be removed only when all are true:

1. Target is running in `canonical_only` mode for one completed rollout wave.
2. No open incidents linked to local env contract.
3. Constructor packets for the target no longer emit alias paths.

## Communication Requirements

Before alias removal in a target repo:

1. Publish migration notice with exact key changes and effective date.
2. Include rollback instructions and owner contacts.
3. Keep one tagged commit for quick rollback to alias-compatible mode.
