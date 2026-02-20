# Phase 5 - Hardening, Rollout, and Operational Confidence

## P5.1 Stress and Race Coverage (`tests/superloop.bats`)
1. [ ] Add repeat-run stress cases to detect flaky ordering/counting behavior in async fan-out.
2. [ ] Add race-focused tests with mixed fast/slow child completions and intermittent failures.
3. [ ] Add CI-stable assertions that detect missing concurrency without overfitting to host load.

## P5.2 Observability Rollups (`src/50-events.sh`, `src/60-commands.sh`, `README.md`)
1. [ ] Extend run-summary/timeline/status rollups with async scheduler metrics (queue depth, cancellation counts, retry totals).
2. [ ] Document how to interpret async delegation metrics during incident/debug workflows.
3. [ ] Ensure rollups distinguish scheduler cancellations from runner failures/timeouts.

## P5.3 Backward Compatibility and Migration (`README.md`, `CHANGELOG.md`)
1. [ ] Add migration notes for users who relied on prior parallel wake coercion behavior.
2. [ ] Document default settings and safe rollout recommendations (`serial` baseline, bounded parallel pilot).
3. [ ] Record release notes for async fan-out behavior change and known caveats.

## P5.4 Canary / Smoke Operationalization (`scripts/`, `.github/workflows/ci.yml`)
1. [ ] Add deterministic async delegation smoke path suitable for CI gating.
2. [ ] Ensure smoke run validates both concurrency behavior and deterministic artifact outputs.
3. [ ] Keep runtime budget bounded so CI remains stable.

## P5.V Validation / Acceptance Tests
1. [ ] Full `bats tests/superloop.bats` suite passes with async fan-out enabled paths.
2. [ ] New async smoke/canary command passes in local and CI environments.
3. [ ] `./superloop.sh status --repo . --loop <async-loop> --summary` exposes expected async rollup fields.
4. [ ] Documentation and changelog entries accurately describe new semantics and limits.
