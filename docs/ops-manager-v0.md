# Ops Manager V0 Contract (Superloop + Sprites)

## Purpose
This document defines the V0 manager/runtime contract for operating Superloop runs from outside a Sprite sandbox VM.

Primary managed unit:
- `Loop Run`

Default isolation policy:
- one loop run per sprite VM

## Contract Surfaces
V0 exports two envelope types described by `schema/ops-manager.contract.schema.json`:

1. `loop_run_snapshot`
- point-in-time lifecycle projection for one loop id
- includes run identity, manager health signals, and artifact metadata

2. `loop_run_event`
- incremental event envelope from `.superloop/loops/<loop>/events.jsonl`
- cursor-aware, supports polling without event duplication

## Required Runtime Artifacts
Required for V0 snapshot/event ingestion:

- `.superloop/loops/<loop>/events.jsonl`

Optional but consumed when present:

- `.superloop/loops/<loop>/run-summary.json`
- `.superloop/state.json`
- `.superloop/active-run.json`
- `.superloop/loops/<loop>/approval.json`

Adapter scripts fail closed when required artifacts are missing.

## Adapter Commands

### Snapshot
```bash
scripts/ops-manager-loop-run-snapshot.sh \
  --repo /path/to/repo \
  --loop my-loop
```

Options:
- `--run-id <id>`: override inferred run id
- `--pretty`: formatted JSON output

### Incremental Events
```bash
scripts/ops-manager-poll-events.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --cursor-file /tmp/my-loop.cursor.json
```

Options:
- `--from-start`: ignore existing cursor and replay from first event
- `--max-events <n>`: cap events emitted in one poll

## Manager Core Commands

### Project State
```bash
scripts/ops-manager-project-state.sh \
  --repo /path/to/repo \
  --loop my-loop
```

Purpose:
- Computes canonical manager lifecycle projection from snapshot/event envelopes.
- Writes state to `.superloop/ops-manager/<loop>/state.json`.

### Reconcile
```bash
scripts/ops-manager-reconcile.sh \
  --repo /path/to/repo \
  --loop my-loop
```

Purpose:
- Executes snapshot + incremental poll + projection in one pass.
- Maintains cursor and state under `.superloop/ops-manager/<loop>/`.
- Emits reconcile telemetry and health projection artifacts under `.superloop/ops-manager/<loop>/telemetry/`.
- Computes reason-coded manager health (`healthy|degraded|critical`) and writes `.superloop/ops-manager/<loop>/health.json`.

Observability thresholds:
- `--threshold-profile <strict|balanced|relaxed>`
- `--thresholds-file <path>`
- `--drift-min-confidence <low|medium|high>`
- `--drift-required-streak <n>`
- `--drift-summary-window <n>`
- `--drift-state-file <path>`
- `--drift-history-file <path>`
- `--degraded-ingest-lag-seconds <n>`
- `--critical-ingest-lag-seconds <n>`
- `--degraded-transport-failure-streak <n>`
- `--critical-transport-failure-streak <n>`

Threshold precedence:
1. Explicit threshold flags (`--degraded-*`, `--critical-*`)
2. Selected threshold profile (`--threshold-profile` or `OPS_MANAGER_THRESHOLD_PROFILE`)
3. Profile catalog default (`defaultProfile` in thresholds file)

Profile catalog default path:
- `config/ops-manager-threshold-profiles.v1.json`

### Control Intent
```bash
scripts/ops-manager-control.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --intent cancel
```

Supported intents:
- `cancel`
- `approve`
- `reject`

Service transport example:
```bash
scripts/ops-manager-control.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --intent approve \
  --transport sprite_service \
  --service-base-url http://127.0.0.1:8787 \
  --service-token "$OPS_MANAGER_SERVICE_TOKEN" \
  --idempotency-key approve-my-loop-001
```

Confirmation:
- `scripts/ops-manager-confirm-intent.sh` is used by default.
- `--no-confirm` skips confirmation and records `executed_unconfirmed`.
- Control telemetry is appended to `.superloop/ops-manager/<loop>/telemetry/control.jsonl`.

### Operator Status
```bash
scripts/ops-manager-status.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --pretty
```

Purpose:
- Provides operator-facing lifecycle + health summary for one loop run.
- Normalizes state, health, cursor, latest control, and latest reconcile telemetry.
- Includes tuning guidance fields from telemetry summaries (`recommendedProfile`, `confidence`, `rationale`).
- Includes profile-drift state/action fields when drift artifacts are present.
- Includes alert delivery summary fields from dispatch artifacts (`alerts.dispatch`, `alerts.lastDelivery`).
- Includes visibility summaries for heartbeat, sequence diagnostics, invocation audit, and trace linkage (`visibility.*`).

Visibility summary fields:
- `visibility.heartbeat`: `freshnessStatus`, `reasonCode`, `lastHeartbeatAt`, `heartbeatLagSeconds`, `updatedAt`, `transport`, `traceId`.
- `visibility.sequence`: `status`, `reasonCode`, `driftActive`, `violations`, `snapshotCurrent`, `eventsLast`, `updatedAt`, `transport`, `traceId`.
- `visibility.invocationAudit`: latest control invocation audit record summary (`intent`, `transport`, `idempotencyKey`, execution/confirmation/outcome status, `traceId`).
- `visibility.trace`: latest trace surface across control/reconcile/heartbeat/sequence/alert artifacts and `sharedTraceId` when all present traces agree.

### Threshold Profile Resolver
```bash
scripts/ops-manager-threshold-profile.sh --profile strict --pretty
```

Purpose:
- Resolves profile values from a versioned profile catalog.
- Enforces fail-closed behavior for unknown/invalid profiles.
- Lists available profiles via `--list`.

### Alert Sink Config Resolver
```bash
scripts/ops-manager-alert-sink-config.sh --pretty
scripts/ops-manager-alert-sink-config.sh --category health_critical --severity critical --pretty
```

Purpose:
- Resolves a versioned alert sink catalog with routing policy and category severity mapping.
- Validates sink definitions and route references with fail-closed behavior.
- Validates env-secret references for enabled sinks (can be bypassed with `--no-env-check`).

Config file precedence:
1. Explicit `--config-file`
2. `OPS_MANAGER_ALERT_SINKS_FILE`
3. `config/ops-manager-alert-sinks.v1.json`

### Alert Dispatch
```bash
scripts/ops-manager-alert-dispatch.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --alert-config-file config/ops-manager-alert-sinks.v1.json \
  --pretty
```

Purpose:
- Consumes new rows from `.superloop/ops-manager/<loop>/escalations.jsonl` using cursor-style offsets.
- Resolves dispatch policy via alert sink config and routes to `webhook`, `slack`, and `pagerduty_events`.
- Persists dispatch state and per-attempt delivery telemetry for operator triage.
- Runs automatically in `scripts/ops-manager-reconcile.sh` when `--alerts-enabled true` (default).

### Telemetry Summary
```bash
scripts/ops-manager-telemetry-summary.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --window 200 \
  --pretty
```

Purpose:
- Summarizes reconcile/control telemetry over a bounded recent window.
- Emits profile recommendation + confidence for dogfood threshold tuning.

### Profile Drift Evaluator
```bash
scripts/ops-manager-profile-drift.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --applied-profile balanced \
  --recommended-profile strict \
  --recommendation-confidence medium \
  --required-streak 3 \
  --summary-window 200 \
  --pretty
```

Purpose:
- Evaluates profile mismatch drift with confidence/streak gating.
- Persists current drift state and appends drift history telemetry.
- Emits `profile_drift_detected` escalations when drift transitions active.

## Fleet Orchestration Commands (Phase 8 + Phase 9 Baseline)

### Fleet Registry
```bash
scripts/ops-manager-fleet-registry.sh \
  --repo /path/to/repo \
  --pretty
```

Purpose:
- Validates and normalizes `.superloop/ops-manager/fleet/registry.v1.json`.
- Enforces fail-closed checks for loop metadata, transport settings, and policy contracts.
- Supports loop-level inspection via `--loop <loop-id>`.

Fleet policy contract fields:
- `policy.mode`: `advisory` (default) or `guarded_auto`.
- `policy.suppressions`: loop/global suppression category mappings (`reconcile_failed`, `health_critical`, `health_degraded`).
- `policy.noiseControls.dedupeWindowSeconds`: advisory candidate cooldown window (default `300`).
- `policy.autonomous.allow.categories`: autonomous candidate category allowlist (default `["reconcile_failed","health_critical"]`).
- `policy.autonomous.allow.intents`: autonomous intent allowlist (default `["cancel"]`).
- `policy.autonomous.thresholds.minSeverity`: minimum severity gate (`critical|warning|info`, default `critical`).
- `policy.autonomous.thresholds.minConfidence`: minimum confidence gate (`high|medium|low`, default `high`).
- `policy.autonomous.safety.maxActionsPerRun`: autonomous action cap per fleet run (default `1`).
- `policy.autonomous.safety.maxActionsPerLoop`: autonomous action cap per loop (default `1`).
- `policy.autonomous.safety.cooldownSeconds`: autonomous loop/category cooldown window (default `300`).
- `policy.autonomous.safety.killSwitch`: hard-disable autonomous dispatch while preserving advisory/manual paths (default `false`).
- `policy.autonomous.governance.actor`: operator/system identity that authorized the guarded autonomous policy change (required when `policy.mode = guarded_auto`).
- `policy.autonomous.governance.approvalRef`: approval/change reference id (required when `policy.mode = guarded_auto`).
- `policy.autonomous.governance.rationale`: human-readable reason for the policy change (required when `policy.mode = guarded_auto`).
- `policy.autonomous.governance.changedAt`: ISO-8601 timestamp for the policy change decision (required when `policy.mode = guarded_auto`).
- `policy.autonomous.governance.reviewBy`: ISO-8601 governance review deadline; must be after `changedAt` and in the future (required when `policy.mode = guarded_auto`).
- `policy.autonomous.governance.reviewWindowDays`: normalized derived review window (`reviewBy - changedAt`, days).
- `policy.autonomous.rollout.canaryPercent`: deterministic cohort percentage for autonomous dispatch (`0..100`, default `100`).
- `policy.autonomous.rollout.scope.loopIds`: optional loop allowlist limiting autonomous rollout scope (default `[]`, meaning all loops).
- `policy.autonomous.rollout.selector.salt`: deterministic cohort selector salt (default `fleet-autonomous-rollout-v1`).
- `policy.autonomous.rollout.pause.manual`: operator-controlled rollout pause flag that forces manual-only handoff (default `false`).
- `policy.autonomous.rollout.autoPause.enabled`: telemetry-driven autonomous pause enable flag (default `true`).
- `policy.autonomous.rollout.autoPause.lookbackExecutions`: number of recent autonomous handoff executions sampled for spike detection (default `5`).
- `policy.autonomous.rollout.autoPause.minSampleSize`: minimum attempted autonomous intents required before auto-pause can trigger (default `3`).
- `policy.autonomous.rollout.autoPause.ambiguityRateThreshold`: ambiguity rate threshold (`0..1`) that triggers auto-pause (default `0.4`).
- `policy.autonomous.rollout.autoPause.failureRateThreshold`: failure rate threshold (`0..1`) that triggers auto-pause (default `0.4`).

Registry schema reference:
- `schema/ops-manager-fleet.registry.schema.json`

### Fleet Reconcile
```bash
scripts/ops-manager-fleet-reconcile.sh \
  --repo /path/to/repo \
  --max-parallel 2 \
  --deterministic-order \
  --trace-id fleet-trace-001 \
  --pretty
```

Purpose:
- Fans out loop-level `ops-manager-reconcile.sh` across registry entries.
- Captures per-loop outcomes (`status`, `reasonCode`, `healthStatus`, `durationSeconds`, `traceId`).
- Persists fleet rollup state and append-only fleet reconcile telemetry.

### Fleet Policy (Advisory)
```bash
scripts/ops-manager-fleet-policy.sh \
  --repo /path/to/repo \
  --trace-id fleet-trace-001 \
  --handoff-telemetry-file /path/to/repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl \
  --governance-audit-file /path/to/repo/.superloop/ops-manager/fleet/telemetry/policy-governance.jsonl \
  --dedupe-window-seconds 300 \
  --pretty
```

Purpose:
- Evaluates fleet reconcile output and emits advisory candidates only.
- Produces reason-coded candidates for `reconcile_failed`, `health_critical`, and `health_degraded`.
- Applies suppression precedence (`loop` over global `*`) and records suppression scope/source.
- Supports both `advisory` and `guarded_auto` policy modes at the contract layer.
- Supports advisory cooldown dedupe using policy history.
- Classifies unsuppressed candidates as `autonomous.eligible` vs `autonomous.manualOnly` with explicit rejection reasons from allowlist/threshold gates.
- Enforces autonomous safety rails before eligibility (`killSwitch`, `maxActionsPerRun`, `maxActionsPerLoop`, `cooldownSeconds`).
- Applies deterministic rollout cohort gating (scope + canary percentage + selector salt) before autonomous eligibility.
- Applies rollout pause gates (`manual` and telemetry-triggered `autoPause`) while preserving manual handoff intent generation.
- Surfaces governance authority context under `autonomous.governance.*` in policy state.
- Persists immutable governance audit events for autonomous policy initialization, mutation, and mode toggles.
- Persists autonomous eligibility state into policy artifacts and policy history telemetry.

### Fleet Status
```bash
scripts/ops-manager-fleet-status.sh \
  --repo /path/to/repo \
  --pretty
```

Purpose:
- Provides operator fleet posture summary and loop exception buckets.
- Surfaces policy summary and top advisory candidates.
- Surfaces handoff execution outcomes plus autonomous safety-gate decisions/reason counts.
- Surfaces rollout posture (`autonomous.rollout.*`) including cohort buckets and pause/auto-pause metrics.
- Surfaces governance posture (`autonomous.governance.*`) including who changed policy (`changedBy`), when (`changedAt`), why (`why`), and until when (`until`).
- Adds autonomous outcome rollups (`attempted`, `executed`, `ambiguous`, `failed`, `manual_backlog`) across status and latest handoff telemetry summaries.
- Distinguishes suppression-path buckets (`policyGated`, `rolloutGated`, `governanceGated`, `transportGated`) under `autonomous.safetyGateDecisions.byPath` plus normalized `suppressionReasonCodes`.
- Includes trace linkage and per-loop drill-down pointers to loop-level artifacts.

### Fleet Handoff (Operator Control Planning/Execution)
```bash
scripts/ops-manager-fleet-handoff.sh \
  --repo /path/to/repo \
  --pretty
```

```bash
scripts/ops-manager-fleet-handoff.sh \
  --repo /path/to/repo \
  --execute \
  --confirm \
  --intent-id <intent-id> \
  --by <operator-name> \
  --note "incident-<id>: remediation" \
  --pretty
```

```bash
scripts/ops-manager-fleet-handoff.sh \
  --repo /path/to/repo \
  --autonomous-execute \
  --by ops-manager \
  --note "incident-<id>: guarded_auto_dispatch" \
  --pretty
```

Purpose:
- Maps unsuppressed advisory candidates into explicit per-loop control intents.
- Enforces explicit operator confirmation gate (`--execute` requires `--confirm`).
- Supports guarded autonomous dispatch (`--autonomous-execute`) for only `autonomous.eligible` intents when policy mode is `guarded_auto`.
- Applies autonomous retry guard after ambiguous/failed autonomous outcomes, forcing explicit manual confirmation before repeat attempts.
- Propagates fleet trace/idempotency into loop-level control telemetry and invocation audit.
- Persists handoff plan/execution artifacts and telemetry.
- Preserves policy autonomous eligibility classification on generated intents (`autoEligibleIntentCount`, `manualOnlyIntentCount`).
- Keeps manual-only/out-of-policy intents pending and reason-coded; autonomous execution never dispatches them.

### Promotion Gates (Dogfood Decision Automation)
```bash
scripts/ops-manager-promotion-gates.sh \
  --repo /path/to/repo \
  --pretty
```

```bash
scripts/ops-manager-promotion-gates.sh \
  --repo /path/to/repo \
  --window-executions 20 \
  --min-sample-size 20 \
  --max-ambiguity-rate 0.2 \
  --max-failure-rate 0.2 \
  --max-manual-backlog 5 \
  --max-drill-age-hours 168 \
  --fail-on-hold \
  --pretty
```

Purpose:
- Evaluates promotion readiness (`promote` vs `hold`) using deterministic gate checks from fleet status, handoff telemetry, and drill evidence.
- Evaluates five gates: governance posture, autonomous outcome reliability, manual backlog, safety/suppression stability, and drill recency.
- Emits reason-coded failed-gate summaries for remediation (`summary.failedGates`, `summary.reasonCodes`).
- Persists latest decision state and append-only promotion telemetry artifacts.
- Supports CI enforcement mode via `--fail-on-hold` (non-zero exit when decision is `hold`).

### Promotion CI Wrapper (Phase 10 / Phase 2)
```bash
scripts/ops-manager-promotion-ci.sh \
  --repo /path/to/repo \
  --skip-on-missing-evidence \
  --summary-file /path/to/repo/.superloop/ops-manager/fleet/promotion-ci-summary.md \
  --result-file /path/to/repo/.superloop/ops-manager/fleet/promotion-ci-result.json
```

Purpose:
- Wraps `scripts/ops-manager-promotion-gates.sh` for CI-friendly execution and summary generation.
- Emits machine-readable result JSON plus markdown summary suitable for job summaries and operator handoff.
- Supports skip mode for missing evidence (`--skip-on-missing-evidence`) to avoid destructive scheduled failures in repos without live fleet telemetry.
- Preserves strict gating behavior with `--fail-on-hold` when promotion checks should block pipeline progression.

## Sprite Service Transport
Service implementation entrypoint:
- `scripts/ops-manager-sprite-service.py`

Service client helper:
- `scripts/ops-manager-service-client.sh`

Auth:
- shared token via `Authorization: Bearer <token>` or `X-Ops-Token`

Transport retry:
- `--retry-attempts <n>`
- `--retry-backoff-seconds <n>`

Transport mode switch:
- reconcile: `scripts/ops-manager-reconcile.sh --transport <local|sprite_service> ...`
- control: `scripts/ops-manager-control.sh --transport <local|sprite_service> ...`

## Manager Persistence Paths
- `.superloop/ops-manager/<loop>/state.json` - projected lifecycle state.
- `.superloop/ops-manager/<loop>/cursor.json` - incremental event cursor.
- `.superloop/ops-manager/<loop>/health.json` - latest health status + reason codes.
- `.superloop/ops-manager/<loop>/heartbeat.json` - latest runtime heartbeat freshness projection.
- `.superloop/ops-manager/<loop>/sequence-state.json` - latest envelope sequence diagnostics state.
- `.superloop/ops-manager/<loop>/intents.jsonl` - control intent execution log.
- `.superloop/ops-manager/<loop>/escalations.jsonl` - divergence/escalation records.
- `.superloop/ops-manager/<loop>/profile-drift.json` - current profile drift state.
- `.superloop/ops-manager/<loop>/alert-dispatch-state.json` - latest alert dispatch summary and cursor offsets.
- `.superloop/ops-manager/<loop>/telemetry/reconcile.jsonl` - reconcile attempt telemetry.
- `.superloop/ops-manager/<loop>/telemetry/control.jsonl` - control attempt telemetry.
- `.superloop/ops-manager/<loop>/telemetry/control-invocations.jsonl` - detailed control invocation audit trail.
- `.superloop/ops-manager/<loop>/telemetry/heartbeat.jsonl` - heartbeat ingestion/freshness telemetry history.
- `.superloop/ops-manager/<loop>/telemetry/sequence.jsonl` - sequence diagnostic telemetry history.
- `.superloop/ops-manager/<loop>/telemetry/profile-drift.jsonl` - profile drift history.
- `.superloop/ops-manager/<loop>/telemetry/alerts.jsonl` - alert delivery attempts/outcomes and reason codes.
- `.superloop/ops-manager/<loop>/telemetry/transport-health.json` - rolling transport failure streak state.
- `.superloop/ops-manager/fleet/registry.v1.json` - fleet membership + transport/policy metadata.
- `.superloop/ops-manager/fleet/state.json` - latest fleet reconcile rollup.
- `.superloop/ops-manager/fleet/policy-state.json` - latest advisory policy candidates + suppression state.
- `.superloop/ops-manager/fleet/handoff-state.json` - latest fleet operator handoff plan/execution state.
- `.superloop/ops-manager/fleet/promotion-state.json` - latest guarded-autonomous promotion decision projection.
- `.superloop/ops-manager/fleet/drills/promotion.v1.json` - required drill evidence state for promotion recency checks.
- `.superloop/ops-manager/fleet/telemetry/reconcile.jsonl` - fleet reconcile attempt history.
- `.superloop/ops-manager/fleet/telemetry/policy.jsonl` - fleet policy evaluation history.
- `.superloop/ops-manager/fleet/telemetry/policy-history.jsonl` - fleet policy candidate suppression/dedupe history.
- `.superloop/ops-manager/fleet/telemetry/policy-governance.jsonl` - immutable fleet policy governance change history.
- `.superloop/ops-manager/fleet/telemetry/handoff.jsonl` - fleet handoff plan/execution history.
- `.superloop/ops-manager/fleet/telemetry/promotion.jsonl` - append-only guarded-autonomous promotion decision history.
- `.superloop/ops-manager/fleet/promotion-ci-result.json` - latest CI wrapper JSON decision output (`promote|hold|skipped`).
- `.superloop/ops-manager/fleet/promotion-ci-summary.md` - latest CI wrapper markdown summary for operator workflow/step summaries.
- `config/ops-manager-threshold-profiles.v1.json` - threshold profile catalog (repo-level, versioned).
- `config/ops-manager-alert-sinks.v1.json` - alert sink routing/catalog config (repo-level, versioned).
- `schema/ops-manager-alert-sinks.config.schema.json` - JSON schema reference for alert sink config.
- `schema/ops-manager-fleet.registry.schema.json` - JSON schema reference for fleet registry artifact.

## Health Reason Codes
Current reason-code surface used in health and escalation artifacts:
- `transport_unreachable`
- `ingest_stale`
- `control_ambiguous`
- `control_failed_command`
- `divergence_detected`
- `invalid_transport_payload`
- `projection_failed`
- `reconcile_failed`
- `profile_drift_detected`

## Fleet Reason Codes
Fleet state/policy/status artifacts may include:
- `fleet_partial_failure`
- `fleet_reconcile_failed`
- `fleet_health_critical`
- `fleet_health_degraded`
- `fleet_loop_skipped`
- `fleet_action_required`
- `fleet_actions_suppressed`
- `fleet_actions_policy_suppressed`
- `fleet_actions_deduped`
- `fleet_auto_candidates_eligible`
- `fleet_auto_candidates_blocked`
- `fleet_auto_candidates_rollout_gated`
- `fleet_auto_candidates_paused`
- `fleet_auto_candidates_autopause_triggered`
- `fleet_auto_kill_switch_enabled`
- `fleet_auto_candidates_safety_blocked`
- `fleet_handoff_action_required`
- `fleet_handoff_no_action`
- `fleet_handoff_confirmation_pending`
- `fleet_handoff_partial_mapping`
- `fleet_handoff_unmapped_candidates`
- `fleet_handoff_retry_guarded`
- `fleet_handoff_auto_eligible_intents`
- `fleet_handoff_executed`
- `fleet_handoff_execution_ambiguous`
- `fleet_handoff_execution_failed`

## Promotion Gate Reason Codes
Promotion decision artifacts may include:
- `promotion_policy_mode_not_guarded_auto`
- `promotion_governance_posture_not_active`
- `promotion_governance_blocks_autonomous`
- `promotion_governance_authority_missing`
- `promotion_governance_review_deadline_missing`
- `promotion_governance_review_expired`
- `promotion_handoff_telemetry_missing`
- `promotion_handoff_telemetry_invalid`
- `promotion_autonomous_sample_insufficient`
- `promotion_autonomous_attempts_zero`
- `promotion_autonomous_ambiguity_rate_exceeded`
- `promotion_autonomous_failure_rate_exceeded`
- `promotion_manual_backlog_unavailable`
- `promotion_manual_backlog_exceeded`
- `promotion_autopause_active`
- `promotion_suppression_paths_missing`
- `promotion_drill_state_missing`
- `promotion_drill_state_invalid`
- `promotion_drill_missing_<id>`
- `promotion_drill_not_passed_<id>`
- `promotion_drill_timestamp_invalid_<id>`
- `promotion_drill_stale_<id>`

## Alert Dispatch Reason Codes
Current alert dispatch telemetry/state may include:
- `invalid_escalation_json`
- `missing_escalation_category`
- `route_resolution_failed`
- `invalid_route_resolution`
- `severity_below_min`
- `no_dispatchable_sinks`
- `missing_secret`
- `http_error`
- `request_failed`
- `unsupported_sink_type`
- `invalid_sink_result`
- `sink_dispatch_failed`
- `partial_dispatch_failure`
- `dispatch_failed`
- `alert_dispatch_failed`

## Compatibility and Versioning Rules
- `schemaVersion` is required and currently fixed to `v1`.
- New fields may be added only as backward-compatible additions.
- Breaking changes require a new schema version and dual-read support during migration.
- Manager logic must key off explicit lifecycle fields and not parse free-form text output.

## Failure Behavior
The adapters are intentionally fail-closed for contract safety:

- missing required artifact root or required event file: non-zero exit
- invalid JSON in source artifacts: non-zero exit
- cursor offset ahead of available events: non-zero exit (explicit reset required)

## Dogfood Promotion Gates
Guarded autonomous mode is dogfood-only by default. Promotion toward broader beta exposure must satisfy all gates below for a trailing review window (recommended: 7 days).

- Governance posture gate:
  - `autonomous.governance.posture` remains `active` for promoted fleets.
  - no `autonomous_governance_authority_missing`, `autonomous_governance_review_deadline_missing`, or `autonomous_governance_review_expired` reason codes.
  - evidence: `scripts/ops-manager-fleet-status.sh --repo /path/to/repo --pretty` and `.superloop/ops-manager/fleet/telemetry/policy-governance.jsonl`.
- Outcome reliability gate:
  - autonomous ambiguity and failure rates remain below agreed SLOs.
  - recommendation: ambiguity rate <= `0.20`, failure rate <= `0.20` over last 20 autonomous executions.
  - evidence: `.superloop/ops-manager/fleet/telemetry/handoff.jsonl` and `autonomous.outcomeRollup`.
- Manual backlog gate:
  - `manual_backlog` remains bounded and operator-confirmation queue does not trend upward.
  - recommendation: backlog <= `5` and no sustained growth across consecutive reconcile windows.
  - evidence: `autonomous.outcomeRollup.manual_backlog`, `handoff.summary.pendingConfirmationCount`.
- Safety-gate stability:
  - no sustained autonomous auto-pause without an active incident.
  - rollout/safety suppression paths are explainable (`policyGated`, `rolloutGated`, `governanceGated`, `transportGated`).
  - evidence: `autonomous.rollout.autopause.*`, `autonomous.safetyGateDecisions.byPath.*`.
- Drill recency gate:
  - kill-switch, sprite outage, and ambiguous retry-guard drills pass on current head.
  - evidence: `tests/ops-manager-fleet.bats` drill cases and linked CI runs.

## Operator Notes
- Use snapshot for current lifecycle state.
- Use event polling for real-time progression.
- Use both together to detect divergence between runtime activity and summary state.
