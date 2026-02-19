# Phase 1 - RLMS Canary CI Gate

## P1.1 Canary Assertion Script
1. [x] Create `scripts/assert-rlms-canary.sh` to validate RLMS canary status artifacts.
2. [x] Enforce required status checks:
   1. [x] `reviewer.status.json` has `status == "ok"`.
   2. [x] `reviewer.status.json` has `should_run == true` (configurable).
3. [x] Enforce quality checks against `reviewer.json`:
   1. [x] `.ok == true`.
   2. [x] Citation count threshold (`>= min_citations`).
   3. [x] Non-fallback citation threshold (`>= min_non_fallback_citations`).
   4. [x] Optional highlight pattern check.
4. [x] Return actionable non-zero failures with clear threshold-specific messages.

## P1.2 Deterministic RLMS Mock Commands
1. [x] Create deterministic mock root code script in `scripts/rlms-mock-root.sh`.
2. [x] Create deterministic mock subcall script in `scripts/rlms-mock-subcall.sh`.
3. [x] Ensure root mock emits high-signal citation/highlight output that satisfies canary thresholds.

## P1.3 CI Wiring
1. [x] Extend `.github/workflows/ci.yml` with `rlms-canary` job.
2. [x] In canary job, execute:
   1. [x] `./superloop.sh validate --repo .`
   2. [x] `./superloop.sh run --repo . --loop rlms-canary`
3. [x] Make run deterministic in CI by patching canary role runner to a local shell runner and using RLMS root/subcall env overrides.
4. [x] Invoke `scripts/assert-rlms-canary.sh` and fail CI on assertion violations.

## P1.4 Regression Coverage
1. [x] Add BATS tests for canary assertion script pass/fail paths.
2. [x] Cover failure cases for:
   1. [x] `should_run=false`
   2. [x] low/empty citations
   3. [x] fallback-only citations
   4. [x] missing required highlight pattern

## P1.5 Documentation
1. [x] Update `README.md` RLMS section with canary assertion usage and threshold knobs.

## P1.V Validation
1. [x] Run `bats tests/rlms.bats tests/superloop.bats tests/rlms-canary-gate.bats`.
2. [x] Run `./scripts/build.sh` and ensure generated `superloop.sh` is in sync.
3. [x] Run `./superloop.sh validate --repo .`.
