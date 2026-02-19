# Feature: RLMS Hybrid Runtime Integration (MVP)

## Goal
Implement a working RLMS hybrid execution path in Superloop that roles can invoke for large/information-dense context analysis while preserving existing role and gate governance.

## Scope
- Add loop-level `rlms` schema + validation + runtime parsing.
- Implement `scripts/rlms` executor with persistent Python REPL and bounded recursion.
- Wire hybrid trigger evaluation and role-time invocation in the run loop.
- Persist RLMS artifacts and include them in evidence/run summaries.
- Add focused BATS coverage for trigger behavior and fallback semantics.

## Non-Goals (this iteration)
- No model fine-tuning for native recursion.
- No async sub-call fan-out.
- No new top-level role.
- No strict sandbox/container isolation beyond process-level limits.

## Primary References
- `feat/rlms-integration/initiation/CONTEXT.MD` - full product and architecture context.
- `schema/config.schema.json` - add `rlms` contract.
- `src/56-validate-static.sh` - static checks for RLMS fields.
- `src/60-commands.sh` - runtime parsing, trigger logic, invocation.
- `src/20-prompts.sh` - role prompt context injection for RLMS artifacts.
- `src/10-evidence.sh` - evidence manifest integration.
- `src/50-events.sh` - event and run summary artifact metadata.
- `tests/superloop.bats`, `tests/runner.bats` - behavior regression coverage.

## Architecture
Superloop remains control plane. RLMS is a role-local tool path:
1. Compute RLMS trigger eligibility for current role/iteration.
2. Execute `scripts/rlms` with loop/role context and limits.
3. Write artifacts under `.superloop/loops/<loop-id>/rlms/`.
4. Pass artifact references into role prompts.
5. Continue standard loop regardless of RLMS failure unless policy requires fail-hard.

## Decisions
- Default mode: `hybrid`.
- Default failure behavior: warn + continue.
- Keep JSON outputs deterministic and machine-readable.
- Make RLMS artifact persistence first-class for auditability.

## Risks / Constraints
- Cost/runtime variance from recursive trajectories.
- Generated code execution safety must be bounded tightly.
- Misconfigured thresholds could over/under-trigger RLMS.
- Need to keep compatibility with existing tests and legacy configs.

## Phases
- **Phase 1**: MVP integration (schema, executor, runtime wiring, artifacts, tests).
- **Phase 2**: Hardening and optimization (sandboxing, richer policies, cost controls, optional required-gate integration).
