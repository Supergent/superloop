# Phase 4 - Async Failure, Timeout, Retry, and Cancellation Policy

## P4.1 Timeout and Cancellation Controls (`src/60-commands.sh`)
1. [ ] Implement explicit timeout transitions for child tasks in async scheduler.
2. [ ] Implement cancellation flow for queued and in-flight children triggered by policy or adaptation decisions.
3. [ ] Ensure cancellation is reflected in child status artifacts and wave-level counters.

## P4.2 Retry Policy in Async Mode (`src/60-commands.sh`)
1. [ ] Apply retry limits/backoff consistently when children fail under concurrent execution.
2. [ ] Prevent retry storms by respecting concurrency cap and queue fairness during retries.
3. [ ] Record attempt history and retry rationale in child status artifacts.

## P4.3 Failure Policy Determinism (`src/60-commands.sh`, `README.md`)
1. [ ] Define policy matrix behavior for `warn_and_continue` and `fail_role` under mixed child outcomes.
2. [ ] Ensure role-level and loop-level policy precedence remains explicit in async execution.
3. [ ] Emit clear `delegation_fail_role` / policy-decision events with causality fields.

## P4.4 State Recovery and Idempotency (`src/60-commands.sh`)
1. [ ] Harden scheduler finalization to avoid duplicate completion/failure accounting.
2. [ ] Ensure interrupted runs can be diagnosed from artifacts without ambiguous terminal states.
3. [ ] Guard against partial artifact writes on abrupt child termination.

## P4.V Validation / Acceptance Tests
1. [ ] New test covers timeout -> retry -> terminal failure accounting under parallel mode.
2. [ ] New test covers adaptation/policy cancellation of in-flight and queued children.
3. [ ] New test covers `fail_role` deterministic abort when any child reaches policy-fatal state.
4. [ ] Existing retry/failure tests remain green for serial and current planner-recon paths.
