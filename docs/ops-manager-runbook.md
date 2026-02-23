# Ops Manager Runbook (V0/V1 Transport)

## Scope
Operational procedures for manager core behavior across local and sprite-service transports:
- lifecycle projection
- divergence triage
- control-intent execution and retry
- cursor reset and replay
- service outage fallback

## Quick Paths
- manager state: `.superloop/ops-manager/<loop>/state.json`
- manager cursor: `.superloop/ops-manager/<loop>/cursor.json`
- manager health: `.superloop/ops-manager/<loop>/health.json`
- heartbeat state: `.superloop/ops-manager/<loop>/heartbeat.json`
- sequence state: `.superloop/ops-manager/<loop>/sequence-state.json`
- intent log: `.superloop/ops-manager/<loop>/intents.jsonl`
- profile drift state: `.superloop/ops-manager/<loop>/profile-drift.json`
- alert dispatch state: `.superloop/ops-manager/<loop>/alert-dispatch-state.json`
- reconcile telemetry: `.superloop/ops-manager/<loop>/telemetry/reconcile.jsonl`
- control telemetry: `.superloop/ops-manager/<loop>/telemetry/control.jsonl`
- control invocation audit: `.superloop/ops-manager/<loop>/telemetry/control-invocations.jsonl`
- heartbeat telemetry: `.superloop/ops-manager/<loop>/telemetry/heartbeat.jsonl`
- sequence telemetry: `.superloop/ops-manager/<loop>/telemetry/sequence.jsonl`
- profile drift telemetry: `.superloop/ops-manager/<loop>/telemetry/profile-drift.jsonl`
- alert dispatch telemetry: `.superloop/ops-manager/<loop>/telemetry/alerts.jsonl`
- transport health: `.superloop/ops-manager/<loop>/telemetry/transport-health.json`
- fleet registry: `.superloop/ops-manager/fleet/registry.v1.json`
- fleet state: `.superloop/ops-manager/fleet/state.json`
- fleet policy state: `.superloop/ops-manager/fleet/policy-state.json`
- fleet handoff state: `.superloop/ops-manager/fleet/handoff-state.json`
- fleet reconcile telemetry: `.superloop/ops-manager/fleet/telemetry/reconcile.jsonl`
- fleet policy telemetry: `.superloop/ops-manager/fleet/telemetry/policy.jsonl`
- fleet policy history: `.superloop/ops-manager/fleet/telemetry/policy-history.jsonl`
- fleet governance audit telemetry: `.superloop/ops-manager/fleet/telemetry/policy-governance.jsonl`
- fleet handoff telemetry: `.superloop/ops-manager/fleet/telemetry/handoff.jsonl`
- fleet promotion state: `.superloop/ops-manager/fleet/promotion-state.json`
- fleet promotion apply state: `.superloop/ops-manager/fleet/promotion-apply-state.json`
- fleet promotion apply telemetry: `.superloop/ops-manager/fleet/telemetry/promotion-apply.jsonl`
- fleet promotion CI result: `.superloop/ops-manager/fleet/promotion-ci-result.json`
- fleet promotion orchestration result: `.superloop/ops-manager/fleet/promotion-orchestrate-result.json`
- fleet promotion orchestration summary: `.superloop/ops-manager/fleet/promotion-orchestrate-summary.md`
- threshold profiles: `config/ops-manager-threshold-profiles.v1.json`
- alert sinks config: `config/ops-manager-alert-sinks.v1.json`
- runtime events: `.superloop/loops/<loop>/events.jsonl`

## Standard Reconcile
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --pretty
```

Expected outputs:
- updated projection state file
- updated cursor file
- updated health file
- appended reconcile telemetry

## Operator Status Snapshot
```bash
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --summary-window 200 --pretty
```

Use this as the default first read during incidents; it summarizes lifecycle, health, reason codes, latest control/reconcile outcomes, and tuning guidance (`recommendedProfile`, `confidence`).
Alert delivery fields are included under `alerts.dispatch` and `alerts.lastDelivery`.
Total visibility fields are surfaced under `visibility.heartbeat`, `visibility.sequence`, `visibility.invocationAudit`, and `visibility.trace`.

## Fleet Orchestration Workflow
Use this flow when operating multiple loop runs as one fleet.

1. Validate and inspect fleet registry:
```bash
scripts/ops-manager-fleet-registry.sh --repo /path/to/repo --pretty
```

2. Execute fleet reconcile fan-out:
```bash
scripts/ops-manager-fleet-reconcile.sh \
  --repo /path/to/repo \
  --max-parallel 2 \
  --deterministic-order \
  --pretty
```

3. Evaluate advisory fleet policy:
```bash
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
```

Optional noise-control override:
```bash
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --dedupe-window-seconds 300 --pretty
```

4. Read operator fleet surface:
```bash
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty
```

5. Generate fleet handoff plan from unsuppressed policy candidates:
```bash
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --pretty
```

6. Execute remediations from handoff:
```bash
# Manual operator-approved execution
scripts/ops-manager-fleet-handoff.sh \
  --repo /path/to/repo \
  --execute \
  --confirm \
  --intent-id <intent-id> \
  --by <operator-name> \
  --note "incident-<id>: remediation"
```

```bash
# Guarded autonomous execution (eligible intents only; guarded_auto mode required)
scripts/ops-manager-fleet-handoff.sh \
  --repo /path/to/repo \
  --autonomous-execute \
  --by ops-manager \
  --note "incident-<id>: guarded_auto_dispatch"
```

7. Verify post-action state:
```bash
scripts/ops-manager-fleet-reconcile.sh --repo /path/to/repo --deterministic-order --pretty
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --pretty
```

Expected fleet outputs:
- fleet rollup status + reason codes (`success|partial_failure|failed`)
- per-loop exception buckets (`reconcileFailures`, `criticalLoops`, `degradedLoops`, `skippedLoops`)
- advisory candidate summary with suppression counts
- suppression precedence (`loop` over global `*`) and suppression source details
- advisory cooldown suppression behavior (`advisory_cooldown_active`) for repeated candidates
- deterministic rollout cohort gating surfaces (`autonomous.rollout.candidateBuckets.*`) for canary/scope posture
- rollout pause posture and spike metrics (`autonomous.rollout.pause.*`) for manual and auto-pause state
- governance posture surfaces (`autonomous.governance.*`) with who changed policy, when, why, and review-until deadline
- autonomous outcome rollups (`autonomous.outcomeRollup`, `handoff.summary.autonomousOutcomeRollup`, `latestHandoffTelemetry.autonomousOutcomeRollup`) for attempted/executed/ambiguous/failed/manual backlog tracking
- suppression-path classification surfaces (`autonomous.safetyGateDecisions.byPath.*`) for policy, rollout, governance, and transport gating
- handoff summary of pending/confirmed/failed operator intents
- explicit confirmation gate for manual execution (`--execute` requires `--confirm`)
- guarded autonomous outcomes and safety-gate decisions from `scripts/ops-manager-fleet-status.sh` (`autonomous.*`, `handoff.*`)
- trace-linked pointers to loop-level state/health/cursor/telemetry artifacts

Expected handoff reason codes in this workflow:
- `fleet_handoff_action_required`
- `fleet_handoff_auto_eligible_intents`
- `fleet_handoff_confirmation_pending`
- `fleet_handoff_retry_guarded`
- `fleet_handoff_executed`
- `fleet_handoff_execution_ambiguous`
- `fleet_handoff_execution_failed`

## Guarded Autonomous Governance
Use this policy when enabling or disabling `guarded_auto` execution.

Required governance metadata (fail-closed when `policy.mode` is `guarded_auto`):
- `policy.autonomous.governance.actor`: who authorized the change.
- `policy.autonomous.governance.approvalRef`: approval/change ticket reference.
- `policy.autonomous.governance.rationale`: why the change is being made.
- `policy.autonomous.governance.changedAt`: ISO-8601 policy decision time.
- `policy.autonomous.governance.reviewBy`: ISO-8601 review deadline; must be after `changedAt` and in the future.

Enable when:
- suppression and allowlist policy are reviewed and current
- autonomous safety controls are set (`maxActionsPerRun`, `maxActionsPerLoop`, `cooldownSeconds`)
- on-call owner is available to monitor `fleet-status` and handoff telemetry

Disable when:
- incident requires strict human approval for all remediations
- autonomous dispatch shows repeated ambiguous/failed outcomes
- kill-switch drill is active or service transport is unstable

Rollout controls:
- `policy.autonomous.rollout.scope.loopIds`: restrict autonomous dispatch to specific loops
- `policy.autonomous.rollout.canaryPercent`: deterministic cohort percentage inside the selected scope
- `policy.autonomous.rollout.pause.manual`: immediate operator pause, keeping all intents manual-only
- `policy.autonomous.rollout.autoPause.*`: telemetry-triggered pause on ambiguity/failure spikes

Set guarded autonomous governance metadata:
```bash
jq '.policy.mode = "guarded_auto"
  | .policy.autonomous.governance = {
      actor: "<actor>",
      approvalRef: "<approval-ref>",
      rationale: "<rationale>",
      changedAt: "<changed-at-iso8601>",
      reviewBy: "<review-by-iso8601>"
    }' .superloop/ops-manager/fleet/registry.v1.json > .superloop/ops-manager/fleet/registry.v1.json.tmp
mv .superloop/ops-manager/fleet/registry.v1.json.tmp .superloop/ops-manager/fleet/registry.v1.json
scripts/ops-manager-fleet-registry.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
```

Verify governance audit trail:
```bash
tail -n 20 .superloop/ops-manager/fleet/telemetry/policy-governance.jsonl | jq '.'
```

Hard-disable autonomous dispatch (kill switch):
```bash
jq '.policy.autonomous.safety.killSwitch = true' .superloop/ops-manager/fleet/registry.v1.json > .superloop/ops-manager/fleet/registry.v1.json.tmp
mv .superloop/ops-manager/fleet/registry.v1.json.tmp .superloop/ops-manager/fleet/registry.v1.json
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty
```

Fallback to explicit manual handoff:
```bash
scripts/ops-manager-fleet-handoff.sh \
  --repo /path/to/repo \
  --execute \
  --confirm \
  --intent-id <intent-id> \
  --by <operator-name>
```

Adjust rollout canary and scope:
```bash
jq '.policy.autonomous.rollout.canaryPercent = 25 | .policy.autonomous.rollout.scope.loopIds = ["loop-a","loop-b"]' \
  .superloop/ops-manager/fleet/registry.v1.json > .superloop/ops-manager/fleet/registry.v1.json.tmp
mv .superloop/ops-manager/fleet/registry.v1.json.tmp .superloop/ops-manager/fleet/registry.v1.json
scripts/ops-manager-fleet-registry.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty
```

Manual pause/unpause autonomous rollout:
```bash
# Pause
jq '.policy.autonomous.rollout.pause.manual = true' .superloop/ops-manager/fleet/registry.v1.json > .superloop/ops-manager/fleet/registry.v1.json.tmp
mv .superloop/ops-manager/fleet/registry.v1.json.tmp .superloop/ops-manager/fleet/registry.v1.json

# Unpause
jq '.policy.autonomous.rollout.pause.manual = false' .superloop/ops-manager/fleet/registry.v1.json > .superloop/ops-manager/fleet/registry.v1.json.tmp
mv .superloop/ops-manager/fleet/registry.v1.json.tmp .superloop/ops-manager/fleet/registry.v1.json
```

Auto-pause spike tuning:
```bash
jq '.policy.autonomous.rollout.autoPause = {
  enabled: true,
  lookbackExecutions: 5,
  minSampleSize: 3,
  ambiguityRateThreshold: 0.4,
  failureRateThreshold: 0.4
}' .superloop/ops-manager/fleet/registry.v1.json > .superloop/ops-manager/fleet/registry.v1.json.tmp
mv .superloop/ops-manager/fleet/registry.v1.json.tmp .superloop/ops-manager/fleet/registry.v1.json
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty
```

## Dogfood Promotion Gates
Use this checklist before expanding guarded autonomous mode beyond internal dogfood fleets.

Promotion baseline:
- evaluation window: trailing 7 days
- minimum autonomous sample: 20 execution events
- all gates below must pass with evidence attached

Automated evaluator (recommended):
```bash
scripts/ops-manager-promotion-gates.sh --repo /path/to/repo --pretty
```
CI enforcement mode:
```bash
scripts/ops-manager-promotion-gates.sh --repo /path/to/repo --fail-on-hold --pretty
```
Pass criteria:
- `.summary.decision` is `promote`
- `.summary.failedGates` is empty
- `.summary.reasonCodes` is empty

1. Governance gate (authority and review posture):
```bash
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty | jq '.autonomous.governance'
tail -n 50 .superloop/ops-manager/fleet/telemetry/policy-governance.jsonl | jq '.'
```
Pass criteria:
- posture is `active`
- no governance reason codes: `autonomous_governance_authority_missing`, `autonomous_governance_review_deadline_missing`, `autonomous_governance_review_expired`

2. Autonomous outcome reliability gate:
```bash
jq -s '
  [ .[] | select((.category // "") == "fleet_handoff_execute" and (.execution.mode // "") == "autonomous") ] as $runs
  | ($runs | if length > 20 then .[-20:] else . end) as $window
  | {
      runs: ($window | length),
      attempted: ([ $window[] | (.execution.requestedIntentCount // 0) ] | add // 0),
      executed: ([ $window[] | (.execution.executedCount // 0) ] | add // 0),
      ambiguous: ([ $window[] | (.execution.ambiguousCount // 0) ] | add // 0),
      failed: ([ $window[] | (.execution.failedCount // 0) ] | add // 0)
    }
  | .ambiguityRate = (if .attempted > 0 then (.ambiguous / .attempted) else 0 end)
  | .failureRate = (if .attempted > 0 then (.failed / .attempted) else 0 end)
' .superloop/ops-manager/fleet/telemetry/handoff.jsonl
```
Pass criteria:
- ambiguity rate <= `0.20`
- failure rate <= `0.20`

3. Manual backlog gate:
```bash
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty | jq '.autonomous.outcomeRollup'
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --pretty | jq '.summary | {pendingConfirmationCount, manualOnlyIntentCount}'
```
Pass criteria:
- `manual_backlog` <= `5`
- no sustained upward trend in pending confirmations across the review window

4. Safety and suppression gate:
```bash
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty | jq '.autonomous.safetyGateDecisions'
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty | jq '.autonomous.rollout.pause'
```
Pass criteria:
- no sustained auto-pause (`autonomous.rollout.pause.auto.active`) outside active incidents
- suppression-path reasons are explainable and actioned (`policyGated`, `rolloutGated`, `governanceGated`, `transportGated`)

5. Drill recency gate:
```bash
~/.local/bats-runtime/node_modules/.bin/bats --filter "incident drill kill switch halts autonomous execution and falls back to explicit manual handoff" tests/ops-manager-fleet.bats
~/.local/bats-runtime/node_modules/.bin/bats --filter "incident drill sprite_service outage triggers autonomous auto-pause and reason-coded manual fallback" tests/ops-manager-fleet.bats
~/.local/bats-runtime/node_modules/.bin/bats --filter "incident drill ambiguous autonomous outcomes are retry-guarded to prevent execution storms" tests/ops-manager-fleet.bats
# record the latest drill run evidence used by promotion automation
cat > .superloop/ops-manager/fleet/drills/promotion.v1.json <<'JSON'
{
  "schemaVersion": "v1",
  "updatedAt": "2026-02-23T10:00:00Z",
  "drills": [
    {"id": "kill_switch", "status": "pass", "completedAt": "2026-02-23T10:00:00Z"},
    {"id": "sprite_service_outage", "status": "pass", "completedAt": "2026-02-23T10:00:00Z"},
    {"id": "ambiguous_retry_guard", "status": "pass", "completedAt": "2026-02-23T10:00:00Z"}
  ]
}
JSON
```
Pass criteria:
- all three drills pass on the candidate commit

Promotion decision:
- attach evidence output for all gates to the promotion change record
- include accountable approver and rollback owner
- if any gate fails, remain in guarded dogfood mode and remediate before re-evaluation

## Promotion CI Workflow
Use this when you want recurring or manual promotion checks from GitHub Actions.

Workflow file:
- `.github/workflows/ops-manager-promotion-gates.yml`

Execution modes:
- `workflow_dispatch`: operator-triggered checks with explicit thresholds and enforcement flags.
- `schedule`: recurring checks (defaults to skip-on-missing-evidence to avoid noisy failures in repos without live fleet artifacts).

Wrapper command used by workflow:
```bash
scripts/ops-manager-promotion-ci.sh \
  --repo /path/to/repo \
  --skip-on-missing-evidence \
  --result-file .superloop/ops-manager/fleet/promotion-ci-result.json \
  --summary-file .superloop/ops-manager/fleet/promotion-ci-summary.md
```

Decision semantics:
- `promote`: all gates pass.
- `hold`: one or more gates fail (optional non-zero exit with `--fail-on-hold`).
- `skipped`: required evidence files are missing and skip mode is enabled.

Artifacts:
- `.superloop/ops-manager/fleet/promotion-ci-result.json`
- `.superloop/ops-manager/fleet/promotion-ci-summary.md`

Triage guidance:
- if result is `hold`, use `.summary.failedGates` and `.summary.reasonCodes` to drive remediation in the same order as gate priority (governance -> reliability -> backlog -> safety -> drills).
- if result is `skipped`, verify fleet telemetry/drill evidence collection paths and rerun with valid artifact sources (or disable skip mode for strict environments).

## Promotion Apply Workflow
Use this after a promotion decision to mutate rollout posture in controlled, audited steps.

Apply commands:
```bash
# expand canary rollout by fixed step (requires promotion decision promote)
scripts/ops-manager-promotion-apply.sh \
  --repo /path/to/repo \
  --intent expand \
  --expand-step 25 \
  --by <operator> \
  --approval-ref <change-id> \
  --rationale "guarded rollout expansion" \
  --review-by <review-deadline-iso8601> \
  --idempotency-key <key> \
  --pretty

# resume rollout without changing canary percent (requires promotion decision promote)
scripts/ops-manager-promotion-apply.sh \
  --repo /path/to/repo \
  --intent resume \
  --by <operator> \
  --approval-ref <change-id> \
  --rationale "resume guarded rollout" \
  --review-by <review-deadline-iso8601> \
  --pretty

# rollback to manual pause posture (safety-allowed even when decision is hold)
scripts/ops-manager-promotion-apply.sh \
  --repo /path/to/repo \
  --intent rollback \
  --by <operator> \
  --approval-ref <change-id> \
  --rationale "incident rollback to manual pause" \
  --review-by <review-deadline-iso8601> \
  --pretty
```

Semantics:
- `expand` and `resume` fail closed when latest promotion decision is not `promote`.
- `rollback` is explicitly safety-allowed to force manual pause quickly.
- governance fields are required for every apply operation.
- idempotency key replay returns prior apply record and does not mutate registry again.

Artifacts:
- `.superloop/ops-manager/fleet/promotion-apply-state.json`
- `.superloop/ops-manager/fleet/telemetry/promotion-apply.jsonl`

## Promotion Rollout Orchestration Workflow
Use this when you want one controlled entrypoint for promotion decision evaluation and rollout mutation (`dry_run`, `apply`, `rollback`).

Workflow file:
- `.github/workflows/ops-manager-promotion-rollout.yml`

Orchestration command:
```bash
scripts/ops-manager-promotion-orchestrate.sh \
  --repo /path/to/repo \
  --mode dry_run \
  --skip-on-missing-evidence \
  --result-file .superloop/ops-manager/fleet/promotion-orchestrate-result.json \
  --summary-file .superloop/ops-manager/fleet/promotion-orchestrate-summary.md \
  --pretty
```

```bash
scripts/ops-manager-promotion-orchestrate.sh \
  --repo /path/to/repo \
  --mode apply \
  --apply-intent expand \
  --expand-step 25 \
  --idempotency-key <key> \
  --trace-id <trace-id> \
  --by <operator> \
  --approval-ref <change-id> \
  --rationale "promotion rollout mutation" \
  --review-by <review-deadline-iso8601> \
  --pretty
```

Semantics:
- always executes `scripts/ops-manager-promotion-ci.sh` first and uses that decision as mutation gate input.
- `dry_run` emits preview artifacts only; no policy mutation.
- `apply` executes `expand` or `resume` and requires promotion decision `promote` plus governance metadata.
- `rollback` executes safety rollback (manual pause posture) and still requires governance metadata.
- supports trace/idempotency forwarding to preserve audit continuity across CI + apply layers.

Artifacts:
- `.superloop/ops-manager/fleet/promotion-orchestrate-result.json`
- `.superloop/ops-manager/fleet/promotion-orchestrate-summary.md`
- `.superloop/ops-manager/fleet/promotion-ci-result.json`
- `.superloop/ops-manager/fleet/promotion-ci-summary.md`

Triage guidance:
- if orchestration succeeds, inspect `.status`, `.decision`, `.summary.failedGates`, `.summary.reasonCodes`, and `.apply.record`.
- if orchestration fails before result write, inspect stderr plus promotion CI artifacts (if present) to identify gate/evidence failures.
- for `apply`/`rollback` input failures, fix governance metadata (`--by`, `--approval-ref`, `--rationale`, `--review-by`) and rerun.
- for `skipped` promotion CI decisions, either provide evidence artifacts or disable skip mode for strict environments.

## Fleet Partial-Failure Triage
Use when fleet status is `partial_failure` or `failed`.

1. Check fleet exception buckets:
```bash
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty
```

2. Confirm fleet reason codes:
- `fleet_partial_failure`
- `fleet_reconcile_failed`
- `fleet_health_critical`
- `fleet_health_degraded`
- `fleet_loop_skipped`

Reason-code-driven triage:
- `fleet_partial_failure`: identify failing subset first, then repair only impacted loops.
- `fleet_reconcile_failed`: verify runtime artifacts/service reachability before retry loops.
- `fleet_health_critical`: prioritize cancel intents for affected loops after explicit operator confirmation.
- `fleet_health_degraded`: monitor if transient; otherwise stage targeted handoff intents.
- `fleet_loop_skipped`: verify registry `enabled` flags and intentional skip criteria.

3. Drill into affected loop artifacts:
```bash
jq '.loops[] | select(.status != "success")' .superloop/ops-manager/fleet/state.json
```

4. Build and inspect handoff plan before manual action:
```bash
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --pretty
jq '.intents[] | select(.status == "pending_operator_confirmation")' .superloop/ops-manager/fleet/handoff-state.json
```

5. Execute only approved intents:
```bash
scripts/ops-manager-fleet-handoff.sh \
  --repo /path/to/repo \
  --execute \
  --confirm \
  --intent-id <intent-id> \
  --by <operator-name>
```

6. Reconcile failing loops directly (loop-level replay/fallback), if still needed:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --from-start --pretty
```

7. Re-run fleet workflow after loop-level remediation:
```bash
scripts/ops-manager-fleet-reconcile.sh --repo /path/to/repo --deterministic-order --pretty
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --pretty
```

## Fleet Sprite Transport Outage Drill
Use when `sprite_service` loops fail due transport/service outages.

1. Identify outage signatures in fleet reason codes and loop outcomes:
- fleet-level: `fleet_reconcile_failed`, `fleet_partial_failure`
- loop-level: `transport_unreachable`, `invalid_transport_payload`, `reconcile_failed`

2. Isolate impacted service loops:
```bash
jq '.results[] | select(.transport == "sprite_service" and .status != "success") | {loopId, reasonCode, healthStatus}' .superloop/ops-manager/fleet/state.json
```

3. Verify autonomous auto-pause posture and operator fallback reasons:
```bash
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
jq '{autoPauseActive: .autonomous.rollout.pause.auto.active, autoPauseReasons: .autonomous.rollout.pause.auto.reasons, reasonCodes: .reasonCodes}' .superloop/ops-manager/fleet/policy-state.json
jq '.candidates[] | {loopId, candidateId, autonomousReasons: .autonomous.reasons, manualOnly: .autonomous.manualOnly}' .superloop/ops-manager/fleet/policy-state.json
```

Expected signals:
- `autonomous.rollout.pause.auto.active = true`
- candidate reasons include `autonomous_rollout_paused_auto` and `autonomous_autopause_failure_spike`
- policy reason codes include `fleet_auto_candidates_paused` and `fleet_auto_candidates_autopause_triggered`

4. For urgent intervention, run local fallback control per loop:
```bash
scripts/ops-manager-control.sh --repo /path/to/repo --loop <loop-id> --intent cancel --transport local
```

5. Replay affected loops locally to recover observability signal:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --transport local --from-start --pretty
```

6. After service recovery, restore declared transport in registry, then re-run full fleet workflow and handoff verification:
```bash
scripts/ops-manager-fleet-registry.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-reconcile.sh --repo /path/to/repo --deterministic-order --pretty
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --pretty
```

## Fleet Ambiguous Outcome Retry-Storm Drill
Use when autonomous execution returns repeated `ambiguous` or `failed_command` outcomes.

1. Inspect latest autonomous execution outcomes:
```bash
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --pretty
jq '.execution.results[] | {intentId, status, reasonCode}' .superloop/ops-manager/fleet/handoff-state.json
```

2. Re-run autonomous execution and verify retry guard blocks storm retries:
```bash
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --autonomous-execute --by ops-manager --pretty
```

Expected signals:
- `execution.requestedIntentCount = 0` for guarded intents
- `summary.pendingConfirmationCount` remains > 0
- handoff reason codes include `fleet_handoff_retry_guarded` and `fleet_handoff_confirmation_pending`
- guarded intents include `autonomous_retry_guard_ambiguous` or `autonomous_retry_guard_failed`

3. Execute guarded intents only via explicit manual confirmation:
```bash
scripts/ops-manager-fleet-handoff.sh \
  --repo /path/to/repo \
  --execute \
  --confirm \
  --intent-id <intent-id> \
  --by <operator-name>
```

## Fleet Transport Parity Checks
Use when the same fleet includes both `local` and `sprite_service` loops.

1. Verify each loop transport declaration in registry:
```bash
jq '.loops[] | {loopId, transport, service: .service}' .superloop/ops-manager/fleet/registry.v1.json
```

2. For `sprite_service` loops, verify service reachability and token env wiring before fleet reconcile.

3. Run fleet reconcile and confirm both transport classes report expected health/status:
```bash
scripts/ops-manager-fleet-reconcile.sh --repo /path/to/repo --deterministic-order --pretty
jq '.results[] | {loopId, transport, status, healthStatus, reasonCode}' .superloop/ops-manager/fleet/state.json
```

## Fleet Suppression Governance
Use this workflow to add/remove policy suppressions without hiding real risk.

1. Snapshot current registry and policy surfaces:
```bash
cp .superloop/ops-manager/fleet/registry.v1.json .superloop/ops-manager/fleet/registry.v1.backup.json
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --pretty
```

2. Edit suppressions in `.superloop/ops-manager/fleet/registry.v1.json`:
- loop-specific scope: `policy.suppressions.<loopId>`
- global scope: `policy.suppressions.*`
- allowed categories only: `reconcile_failed`, `health_critical`, `health_degraded`

3. Validate registry change before applying:
```bash
scripts/ops-manager-fleet-registry.sh --repo /path/to/repo --pretty
```

4. Recompute policy + handoff and verify expected suppression effect:
```bash
scripts/ops-manager-fleet-policy.sh --repo /path/to/repo --pretty
scripts/ops-manager-fleet-handoff.sh --repo /path/to/repo --pretty
jq '.candidates[] | {loopId, category, suppressed, suppressionScope, suppressionReason}' .superloop/ops-manager/fleet/policy-state.json
```

5. Confirm no unintended suppression drift:
- if an intent disappears from `handoff-state.json`, confirm it is intentionally suppressed
- if `fleet_actions_policy_suppressed` appears, confirm change scope and review window are documented

Audit trail expectations for each suppression change:
- change owner (`who`)
- timestamp (`when`)
- scope (`loopId` or `*`)
- categories affected (`what`)
- incident/ticket reference and rationale (`why`)
- planned expiry or review date (`until when`)
- before/after evidence links from:
  - `.superloop/ops-manager/fleet/policy-state.json`
  - `.superloop/ops-manager/fleet/telemetry/policy-history.jsonl`
  - `.superloop/ops-manager/fleet/handoff-state.json`
  - `.superloop/ops-manager/fleet/telemetry/handoff.jsonl`

## Total Visibility Triage
Use this flow when the operator needs end-to-end visibility from runtime heartbeat to escalation delivery.

1. Pull status visibility summary:
```bash
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --pretty
```

2. Verify heartbeat freshness surface:
- `visibility.heartbeat.freshnessStatus`: `fresh|degraded|critical`
- `visibility.heartbeat.reasonCode`: expected `runtime_heartbeat_stale` when degraded/critical
- `visibility.heartbeat.lastHeartbeatAt` and `heartbeatLagSeconds`

3. Verify sequence integrity surface:
- `visibility.sequence.status`: expected `ok` or `ordering_drift_detected`
- `visibility.sequence.violations`: inspect for `snapshot_sequence_regression`, `event_sequence_regression`, or missing sequence fields
- `visibility.sequence.traceId`: correlate with reconcile/escalation traces

4. Verify control invocation audit when control operations were issued:
```bash
tail -n 5 .superloop/ops-manager/<loop>/telemetry/control-invocations.jsonl
```
- compare `visibility.invocationAudit.traceId` against `visibility.trace.controlInvocationTraceId`
- confirm execution/confirmation/outcome status before retrying actions

5. Verify trace linkage across visibility and alert surfaces:
- `visibility.trace.reconcileTraceId`
- `visibility.trace.alertTraceId`
- `visibility.trace.sharedTraceId` (non-null means the latest trace surfaces are aligned)

## Profile Drift Triage
Use when policy profile and telemetry recommendation may be diverging.

1. Inspect current drift state:
```bash
jq '.' .superloop/ops-manager/<loop>/profile-drift.json
```

2. Check recent drift evaluations:
```bash
tail -n 20 .superloop/ops-manager/<loop>/telemetry/profile-drift.jsonl
```

3. Read status action guidance:
```bash
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --summary-window 200 --pretty
```

Operator actions for active drift (`status=drift_active`):
- review applied profile vs recommendation and rationale
- keep advisory mode (no automatic profile switching)
- apply explicit profile change only after operator confirmation

## Divergence Triage
1. Inspect current manager projection:
```bash
jq '.' .superloop/ops-manager/<loop>/state.json
```

2. Check divergence flags:
```bash
jq '.divergence' .superloop/ops-manager/<loop>/state.json
```

3. If divergence is true:
- freeze automated control actions for this loop
- replay from start to rebuild context:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --from-start --pretty
```
- if divergence persists, append escalation evidence to `.superloop/ops-manager/<loop>/escalations.jsonl`

4. Confirm health reason surface:
```bash
jq '.health.status, .health.reasonCodes' .superloop/ops-manager/<loop>/state.json
```

Expected reason code for this workflow:
- `divergence_detected`

## Safe Control-Intent Retry
1. Inspect latest intent entries:
```bash
tail -n 5 .superloop/ops-manager/<loop>/intents.jsonl
```

2. Retry only when prior status is `ambiguous` or `failed_command` and runtime state still requires intervention.

3. Execute intent with confirmation:
```bash
scripts/ops-manager-control.sh --repo /path/to/repo --loop <loop-id> --intent cancel
```

4. Reconcile immediately after intent:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id>
```

5. Validate control telemetry and ambiguous outcomes:
```bash
tail -n 5 .superloop/ops-manager/<loop>/telemetry/control.jsonl
```

If latest reason code is `control_ambiguous`, do not repeat actions blindly; inspect runtime artifacts first.

## Cursor Reset and Replay
Use when cursor drift or corrupted cursor JSON is detected.

1. Backup and remove cursor:
```bash
cp .superloop/ops-manager/<loop>/cursor.json .superloop/ops-manager/<loop>/cursor.backup.json
rm -f .superloop/ops-manager/<loop>/cursor.json
```

2. Replay from start:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --from-start --pretty
```

3. Verify cursor offset is monotonic and state no longer flags `cursorRegression`.

## Service Mode Operations
Reconcile using sprite service transport:
```bash
scripts/ops-manager-reconcile.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --transport sprite_service \
  --service-base-url http://127.0.0.1:8787 \
  --service-token "$OPS_MANAGER_SERVICE_TOKEN"
```

Control using sprite service transport:
```bash
scripts/ops-manager-control.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --intent approve \
  --transport sprite_service \
  --service-base-url http://127.0.0.1:8787 \
  --service-token "$OPS_MANAGER_SERVICE_TOKEN" \
  --idempotency-key approve-<loop-id>-001
```

## Service Outage Fallback
If sprite service requests fail after retries:
1. Record the failed attempt in `intents.jsonl` and halt automated interventions.
2. Switch to local transport for critical operations:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --transport local
scripts/ops-manager-control.sh --repo /path/to/repo --loop <loop-id> --intent cancel --transport local
```
3. After service recovery, replay from start or stable cursor and re-enable service mode.

Operational reason codes expected in this flow:
- `transport_unreachable`
- `invalid_transport_payload`
- `ingest_stale` (if outage delays event freshness long enough)

## Partial Visibility Fallback
Use when status shows incomplete visibility (for example, missing `visibility.heartbeat` or `visibility.sequence`) due runtime/service gaps.

1. Confirm raw runtime artifacts exist:
```bash
ls -l .superloop/loops/<loop>/heartbeat.v1.json .superloop/loops/<loop>/events.jsonl
```

2. Force a full replay to repopulate sequence + heartbeat projections:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --from-start --pretty
```

3. If service mode is unstable, run fallback reconcile locally until transport recovers:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --transport local --from-start
```

4. Re-run status and ensure visibility surfaces are restored:
```bash
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --pretty
```

## Alert Sink Config Baseline
Resolve config and route behavior before enabling external dispatch:

```bash
scripts/ops-manager-alert-sink-config.sh --pretty
scripts/ops-manager-alert-sink-config.sh --category health_critical --severity critical --pretty
```

Secret env checks:
- Enabled sinks require configured env-secret references to be set.
- Resolver is fail-closed by default when enabled sink secrets are missing.
- Use `--no-env-check` only for dry-run catalog inspection.

Config precedence:
1. `--config-file`
2. `OPS_MANAGER_ALERT_SINKS_FILE`
3. `config/ops-manager-alert-sinks.v1.json`

## Alert Delivery Triage
Use when escalations are being generated but expected external notifications are not observed.

1. Check current delivery summary in status:
```bash
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --pretty
```

2. Inspect dispatch state:
```bash
jq '.' .superloop/ops-manager/<loop>/alert-dispatch-state.json
```

3. Inspect recent delivery telemetry:
```bash
tail -n 20 .superloop/ops-manager/<loop>/telemetry/alerts.jsonl
```

4. Map reason codes to likely operator actions:
- `missing_secret`: set required sink env vars or disable the sink.
- `route_resolution_failed` / `invalid_route_resolution`: validate `config/ops-manager-alert-sinks.v1.json` against schema and route references.
- `http_error` / `request_failed`: verify endpoint reachability, credentials, and timeout settings.
- `no_dispatchable_sinks`: expected when matching routes only reference disabled sinks.
- `alert_dispatch_failed`: dispatch command failed during reconcile wrapper invocation; rerun dispatch manually after correcting root cause.

5. Manual replay after fix:
```bash
scripts/ops-manager-alert-dispatch.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --alert-config-file config/ops-manager-alert-sinks.v1.json \
  --pretty
```

## Alert Outage Fallback
When downstream sinks are degraded/outage-level:

1. Keep reconcile/control available by temporarily disabling dispatch in reconcile:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --alerts-enabled false
```

2. Continue collecting escalation evidence in:
- `.superloop/ops-manager/<loop>/escalations.jsonl`

3. After sink recovery, replay pending escalations through dispatch:
```bash
scripts/ops-manager-alert-dispatch.sh --repo /path/to/repo --loop <loop-id> --pretty
```

4. Re-enable dispatch and verify status summary reports fresh alert activity:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --alerts-enabled true
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --pretty
```

## Threshold Tuning
Default profile catalog (`config/ops-manager-threshold-profiles.v1.json`):
- `strict`: `120/300` ingest-lag seconds, `1/2` failure streak
- `balanced` (default): `300/900` ingest-lag seconds, `2/4` failure streak
- `relaxed`: `600/1800` ingest-lag seconds, `3/6` failure streak

Telemetry-first tuning workflow:
1. Summarize recent telemetry and inspect recommendation:
```bash
scripts/ops-manager-telemetry-summary.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --window 200 \
  --pretty
```
2. Apply profile on reconcile:
```bash
scripts/ops-manager-reconcile.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --threshold-profile balanced \
  --drift-min-confidence medium \
  --drift-required-streak 3
```
3. If needed, override specific values explicitly (highest precedence):
```bash
scripts/ops-manager-reconcile.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --threshold-profile strict \
  --critical-ingest-lag-seconds 480
```

Precedence rules:
1. explicit threshold flags
2. selected profile (`--threshold-profile` or `OPS_MANAGER_THRESHOLD_PROFILE`)
3. catalog default profile
