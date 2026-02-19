# Feature: RLMS Phase 2 Hardening (Canary + Quality Gates)

## Goal
Add deterministic CI enforcement for RLMS canary behavior so regressions are blocked before merge.

## Scope
- Add a deterministic RLMS canary assertion script for status + quality checks.
- Add CI job wiring to run `rlms-canary` and enforce assertions.
- Add mock RLMS root/subcall command scripts for CI-safe execution.
- Add regression tests for canary assertion behavior.

## Non-Goals (this iteration)
- No fallback runner/model strategy changes.
- No RLMS telemetry/report surface expansion.
- No production rollout changes for additional real loops.

## Primary References
- `feat/rlms-integration/repl-engine/PLAN.MD`: existing REPL RLMS architecture.
- `.superloop/config.json`: canary loop definition (`rlms-canary`).
- `scripts/rlms_worker.py`: sandboxed RLMS REPL runtime.
- `.github/workflows/ci.yml`: CI enforcement pipeline.

## Architecture
CI runs the `rlms-canary` loop with deterministic mock role execution and deterministic RLMS root/subcall scripts. The run emits standard RLMS artifacts. A dedicated assertion script validates both activation/status (`should_run`, `status`) and output quality (`ok`, citations, highlights). CI fails with actionable messages on any threshold violation.

## Decisions
- Keep canary validation as a standalone shell script in `scripts/` for local + CI reuse.
- Use explicit threshold flags/env vars instead of hardcoding values in workflow steps.
- Keep canary deterministic by using local mock scripts instead of external model APIs.

## Risks / Constraints
- Overly strict thresholds can create noisy CI failures.
- Too lenient thresholds can allow low-signal RLMS output to pass.
- CI runtime must remain bounded and not depend on external credentials.

## Phases
- **Phase 1**: CI canary status/quality gate + tests + deterministic mocks.
- **Phase 2**: Fallback strategy + telemetry + rollout policy hardening.
