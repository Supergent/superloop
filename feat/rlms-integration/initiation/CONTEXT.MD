# RLMS Hybrid Integration - Deep Context

## 1. Purpose

This document gives engineers full background on the RLMS integration work for Superloop.
It is written for readers with zero prior context.

Use this as the primary "what and why" reference.
Use `PLAN.MD` and `tasks/PHASE_1.MD` for execution tracking.

## 2. Current System Baseline

Superloop today is a deterministic orchestration harness for software delivery:

- Human-authored spec defines requirements.
- Loop executes `planner -> implementer -> tester -> reviewer`.
- Completion requires explicit promise + passing gates.

Primary strengths of the current design:

- Clear role boundaries.
- Auditable artifacts (`events.jsonl`, `run-summary.json`, `evidence.json`).
- Strong completion controls (tests/checklists/evidence/optional approval).
- Resume/recovery behavior (timeouts, rate-limit handling, stuck detection).

Primary limitation relevant to this feature:

- Roles can struggle when understanding very large or information-dense inputs.
- Existing prompting/context mechanisms are not designed for arbitrarily large prompt processing with symbolic recursion.

## 3. Problem Statement

We need a reliable way for roles to process large context without collapsing role boundaries or weakening completion governance.

Constraints:

- Must preserve Superloop’s current control plane and gates.
- Must avoid introducing a fifth "all-powerful" role.
- Must remain observable and testable.
- Must degrade safely when RLMS fails.

## 4. Why RLMS

Recursive Language Models (RLMS) are an inference pattern where:

- Input context is treated as external state in an environment (REPL).
- The model writes code to inspect/decompose that state.
- The model recursively invokes sub-calls over slices as needed.
- Root loop carries compact metadata, not full long text history.

Operational value for Superloop:

- Better long-context processing for planning, implementation analysis, and review support.
- Maintains model-agnostic orchestration while adding a scalable analysis primitive.
- Supports structured, persistent artifacts that fit existing evidence/logging model.

## 5. Design Decision: Hybrid Trigger Mode

Default trigger mode is **hybrid**:

- Auto-trigger when objective thresholds are exceeded.
- Role-requested trigger for hard cases below thresholds.
- Explicit force-on/force-off policy support.

Why hybrid:

- Auto-only misses tricky low-size but high-complexity tasks.
- Manual-only depends too much on role behavior consistency.
- Hybrid balances reliability and operator control.

## 6. Scope of This Phase

In scope:

- `rlms` config contract (schema + static validation + runtime parsing).
- Deterministic RLMS CLI/executor.
- Role-time RLMS invocation in loop.
- Prompt wiring for RLMS output context files.
- Evidence/logging integration.
- Tests for trigger behavior and failure fallback.

Out of scope:

- Native recursive model fine-tuning.
- Async fan-out recursion and distributed execution.
- Hard security sandboxing (containers/VM isolation) in this first pass.
- Changing completion gate semantics by default.

## 7. Architecture Overview

### 7.1 Control Plane (unchanged)

Superloop remains authoritative for:

- Role sequencing.
- Gate evaluation.
- Completion decision.
- State persistence and audit logs.

### 7.2 Data Plane (new RLMS tool path)

When RLMS is triggered for a role:

1. Superloop computes trigger eligibility (mode + thresholds + overrides).
2. Superloop invokes `scripts/rlms` with role/loop/task context.
3. RLMS worker executes bounded recursive analysis.
4. RLMS writes structured output under `.superloop/loops/<loop-id>/rlms/`.
5. Role prompt receives RLMS artifact paths as additional context.
6. Loop continues regardless of RLMS success/failure (unless explicitly required).

## 8. Config Contract (Planned)

High-level planned shape:

```json
{
  "loops": [
    {
      "rlms": {
        "enabled": true,
        "mode": "hybrid",
        "request_keyword": "RLMS_REQUEST",
        "auto": {
          "max_lines": 2500,
          "max_estimated_tokens": 120000,
          "max_files": 40
        },
        "roles": {
          "planner": true,
          "implementer": true,
          "tester": true,
          "reviewer": true
        },
        "limits": {
          "max_steps": 40,
          "max_depth": 2,
          "timeout_seconds": 240
        },
        "output": {
          "format": "json",
          "require_citations": true
        },
        "policy": {
          "force_on": false,
          "force_off": false,
          "fail_mode": "warn_and_continue"
        }
      }
    }
  ]
}
```

Note: field names may be adjusted during implementation for consistency with existing schema conventions.

## 9. RLMS Output Contract (Planned)

Each run should produce machine-readable output with diagnostics.

Minimal expected fields:

- `ok` (boolean)
- `role`, `loop_id`, `iteration`
- `task_summary`
- `findings` array
- `citations` (file + line ranges where applicable)
- `metrics` (`steps`, `depth`, `duration_ms`, `subcalls`)
- `errors` (if any)

Output location pattern:

- `.superloop/loops/<loop-id>/rlms/<role>-iter-<n>.json`

## 10. Failure Modes and Guardrails

Expected failure classes:

- Python execution/runtime errors.
- Schema/contract output mismatch.
- Timeout/step/depth limit exceeded.
- Sub-call tool/rate-limit issues.

Guardrails:

- Hard limits on steps/depth/timeout.
- Explicit non-zero exits for hard contract violations.
- Standardized error payload for observability.
- Superloop default behavior: log warning, continue role flow.

## 11. Security and Safety

Phase 1 stance:

- Process-level controls only (timeouts, bounded recursion, restricted interface).
- No assumption of trusted generated code.

Future hardening:

- Sandboxed execution environment.
- Explicit filesystem/network restrictions.
- Policy-based allowed operations.

## 12. Observability and Audit

RLMS actions should appear in existing loop observability:

- Events: `rlms_start`, `rlms_end`, `rlms_failed`, `rlms_skipped`.
- Artifact metadata in run summary/evidence.
- Prompt references to RLMS output files for downstream role traceability.

This ensures engineers can answer:

- Why RLMS ran (or did not run).
- What it produced.
- Whether it influenced a role’s decision path.

## 13. Testing Strategy

Required tests in this phase:

- Schema validation for `rlms` fields and boundaries.
- Trigger-mode behavior (auto/manual/hybrid).
- Role integration path writes artifacts.
- Failure fallback behavior does not deadlock loop.
- Evidence manifest includes RLMS artifacts.

Target suites:

- `tests/superloop.bats`
- `tests/runner.bats`
- Additional focused BATS file if clearer.

## 14. Rollout and Operational Plan

Rollout order:

1. Land initiation docs + config shape.
2. Land executor with safe defaults.
3. Wire invocation + artifacts.
4. Land tests.
5. Enable in selected loops via config.

Default deployment posture:

- `enabled: false` unless explicitly configured in loop.
- Hybrid defaults documented for adopters.

## 15. Tradeoffs and Alternatives

Alternative considered: add RLMS as a new top-level role.

Rejected because:

- Blurs ownership boundaries.
- Adds completion ambiguity.
- Duplicates existing reviewer/tester responsibilities.

Chosen approach: RLMS as role-local tool.

Benefits:

- Preserves existing governance model.
- Easier incremental rollout.
- Lower integration risk.

## 16. Definition of Done (Phase 1)

Phase 1 is done when:

- `rlms` config is schema-validated and statically checked.
- RLMS tool executes with bounded recursion and writes structured artifacts.
- Roles can trigger RLMS via hybrid policy.
- RLMS artifacts are visible in prompt context and evidence outputs.
- Tests cover core trigger + fallback behaviors.

## 17. Open Questions for Phase 2+

- Should RLMS output quality become a required completion gate in some loops?
- Should we support asynchronous sub-calls for latency reduction?
- What security boundary is acceptable for generated code execution in production?
- Should we add per-loop cost budgets specifically for RLMS calls?
