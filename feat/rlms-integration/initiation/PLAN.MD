# Feature: RLMS Hybrid Integration

## Goal
Add an RLMS (Recursive Language Model Scaffold) execution path that roles can invoke in hybrid mode (auto-threshold + explicit request) while preserving Superloop’s existing role boundaries and completion gates.

## Scope
- Add `rlms` configuration schema and runtime parsing with per-role policy and trigger thresholds.
- Implement a deterministic RLMS executor (`scripts/rlms`) backed by a persistent Python REPL worker with bounded recursion, timeouts, and structured outputs.
- Integrate RLMS invocation into role execution flow and role prompts.
- Persist RLMS outputs under loop artifacts and include them in evidence manifests.
- Add targeted tests for trigger behavior, artifact generation, and failure fallback.

## Non-Goals (this iteration)
- No native recursive model fine-tuning.
- No asynchronous recursive fan-out.
- No new top-level Superloop role (RLMS remains role-local tooling).
- No hardened container sandboxing beyond process-level limits.

## Primary References
- `schema/config.schema.json` - loop config schema and new `rlms` block.
- `src/60-commands.sh` - run loop orchestration and role execution path.
- `src/20-prompts.sh` - role prompt assembly and context file injection.
- `src/10-evidence.sh` - evidence manifest generation.
- `src/56-validate-static.sh` - static config validation.
- `tests/*.bats` - shell-level loop and gate tests.
- `feat/rlms-integration/initiation/CONTEXT.MD` - deep onboarding and architecture rationale.

## Architecture
RLMS integration introduces a role-local analysis pipeline:
1. Evaluate RLMS trigger policy for current role and iteration.
2. Execute `scripts/rlms` with loop/role/task context and configured limits.
3. Write structured output JSON and execution metadata to `.superloop/loops/<loop-id>/rlms/`.
4. Expose artifact paths to the active role prompt and include artifacts in evidence output.
5. Continue the standard role pipeline even if RLMS fails (with explicit logging/status).

The existing Planner/Implementer/Tester/Reviewer control loop, promise checks, and gates remain unchanged.

## Decisions
- Use **hybrid** trigger mode by default to combine objective thresholds with optional role-requested invocation.
- Keep RLMS as a **tool** inside roles rather than a fifth role to preserve accountability boundaries.
- Require machine-readable RLMS outputs (JSON) with optional citation fields to support evidence and future gate checks.
- Use a persistent Python REPL per RLMS run for symbolic state + recursive sub-calls with explicit max limits.

## Risks / Constraints
- Recursive trajectories can increase runtime/cost variance.
- Executing generated code requires strict step/depth/timeout controls.
- RLMS failures must not derail normal loop progress unless explicitly configured.
- Cross-platform shell/Python behavior must remain compatible with current Superloop test matrix.

## Phases
- **Phase 1**: Ship MVP RLMS hybrid integration (schema, executor, role wiring, evidence, tests).
- **Phase 2**: Hardening pass (sandbox tightening, richer output validation, cost controls, optional gateing on RLMS quality).
