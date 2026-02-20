# Phase 1 - Async Contract and Scheduler Scaffolding

## P1.1 Delegation Contract Clarification (`schema/config.schema.json`, `README.md`)
1. [x] Add explicit concurrency cap semantics for async waves (normalize `max_children` and optional `max_parallel` alias if introduced).
2. [x] Define and document terminal child states required by async runtime (`completed`, `failed`, `timed_out`, `cancelled`, `policy_violation`, `skipped`).
3. [ ] Update docs to state that parallel `wake_policy=on_child_complete` is supported by scheduler semantics (remove coercion language after implementation).
4. [x] Preserve backward compatibility for legacy wake aliases (`immediate`, `after_all`) with explicit normalization notes.

## P1.2 Scheduler State Model (`src/60-commands.sh`, `README.md`)
1. [x] Define an internal child lifecycle state machine and transition rules (pending -> running -> terminal).
2. [x] Define wave-level invariants for async mode (no over-cap dispatch, no double-finalization, deterministic terminal accounting).
3. [x] Add explicit parent adaptation checkpoints in scheduler lifecycle for `on_child_complete`.

## P1.3 Artifact/Event Contract (`src/50-events.sh`, `src/60-commands.sh`)
1. [x] Define event set for scheduler lifecycle (wave dispatch start/end, queue drain, child terminal transition, policy decision).
2. [x] Extend delegation status/index schema to record concurrency cap, scheduler stats, and per-state counts.
3. [ ] Define deterministic aggregation metadata fields (aggregation_order, completion_order, policy_reason).

## P1.4 Test Harness Baseline (`tests/superloop.bats`)
1. [x] Add reusable helper patterns for deterministic async assertions (timestamp overlap + max-concurrency cap checks).
2. [x] Add baseline regression tests that keep existing serial behavior unchanged when `dispatch_mode=serial`.
3. [x] Add guard test ensuring async contract fields are present in delegation status artifacts.

## P1.V Validation / Acceptance Tests
1. [x] `./superloop.sh validate --repo . --schema schema/config.schema.json` passes with async config examples.
2. [x] `bats tests/superloop.bats --filter 'validate accepts delegation configuration with legacy and explicit wake labels'` remains green.
3. [x] New contract test asserts delegation status schema includes scheduler state/count fields.
4. [x] README delegation semantics match schema/runtime behavior with no conflicting coercion language.
