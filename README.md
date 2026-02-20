# Superloop

A bash orchestration harness that runs AI coding agents in an iterative loop until a feature is complete.

```
┌──────────────────────────────────────────────────────────────────┐
│                      HUMAN-IN-THE-LOOP                           │
│  Constructor (/construct-superloop) → spec.md + config.json      │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                    AUTOMATED (superloop run)                     │
│                                                                  │
│   Planner ──► Implementer ──► Tester ──► Reviewer ──┐            │
│      ▲                                              │            │
│      └──────────────────────────────────────────────┘            │
│                    (repeats until complete)                      │
└──────────────────────────────────────────────────────────────────┘
```

## Quick Start

**1. Create a spec** (in Claude Code):

```
/construct-superloop
```

This guides you through creating `spec.md` and `config.json`.

**2. Run the loop:**

```bash
./superloop.sh run --repo /path/to/repo
```

The loop runs until all gates pass: promise emitted, tests pass, checklists complete, evidence exists.

## Feature Initiation (Repository Workflow)

For any new feature in this repo, follow the initiation workflow:
`handbook/features/INITIATION.MD`.

Optional scaffold:

```bash
scripts/init-feature.sh <feature-name> [slug]
```

This creates `feat/<feature-name>/<slug>/PLAN.MD` and `tasks/PHASE_1.MD`.

## How It Works

Each iteration runs four roles in sequence:

| Role | Input | Output | Purpose |
|------|-------|--------|---------|
| **Planner** | spec.md | PLAN.MD, PHASE_*.MD | Decomposes requirements into atomic tasks |
| **Implementer** | PLAN.MD, PHASE_*.MD | Code changes | Executes tasks, checks them off |
| **Tester** | Test results + spec | test-report.md | Analyzes failures, verifies AC coverage |
| **Reviewer** | All artifacts | review.md | Approves completion or requests changes |

The loop completes when the Reviewer outputs `<promise>COMPLETION_TAG</promise>` and all gates pass.

## Config

`.superloop/config.json` controls runners, models, and loops:

```json
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "-"],
      "prompt_mode": "stdin"
    },
    "claude": {
      "command": ["claude"],
      "args": ["--dangerously-skip-permissions", "--print", "-"],
      "prompt_mode": "stdin"
    }
  },
  "role_defaults": {
    "planner": {"runner": "codex", "model": "gpt-5.2-codex", "thinking": "max"},
    "implementer": {"runner": "claude", "model": "claude-sonnet-4-5-20250929", "thinking": "standard"},
    "tester": {"runner": "claude", "model": "claude-sonnet-4-5-20250929", "thinking": "standard"},
    "reviewer": {"runner": "codex", "model": "gpt-5.2-codex", "thinking": "max"}
  },
  "loops": [{
    "id": "my-feature",
    "spec_file": ".superloop/specs/my-feature.md",
    "completion_promise": "SUPERLOOP_COMPLETE",
    "max_iterations": 20,
    "checklists": [],
    "tests": {
      "mode": "on_promise",
      "commands": ["npm test"]
    },
    "evidence": {
      "enabled": false,
      "require_on_completion": false,
      "artifacts": []
    },
    "approval": {
      "enabled": false,
      "require_on_completion": false
    },
    "reviewer_packet": {
      "enabled": true
    },
    "timeouts": {
      "enabled": true,
      "default": 300,
      "planner": 120,
      "implementer": 300,
      "tester": 300,
      "reviewer": 120
    },
    "stuck": {
      "enabled": true,
      "threshold": 3,
      "action": "report_and_stop",
      "ignore": []
    },
    "rlms": {
      "enabled": false,
      "mode": "hybrid",
      "request_keyword": "RLMS_REQUEST",
      "auto": {
        "max_lines": 2500,
        "max_estimated_tokens": 120000,
        "max_files": 40
      },
      "limits": {
        "max_steps": 40,
        "max_depth": 2,
        "timeout_seconds": 240,
        "max_subcalls": 80
      },
      "policy": {
        "force_on": false,
        "force_off": false,
        "fail_mode": "warn_and_continue"
      }
    },
    "delegation": {
      "enabled": false,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "max_children": 1,
      "max_parallel": 1,
      "max_waves": 1,
      "child_timeout_seconds": 300,
      "retry_limit": 0,
      "roles": {
        "planner": {
          "enabled": true,
          "mode": "reconnaissance",
          "max_children": 2
        },
        "implementer": {
          "enabled": true,
          "dispatch_mode": "parallel",
          "wake_policy": "on_wave_complete",
          "max_children": 3,
          "max_parallel": 2
        }
      }
    },
    "roles": {
      "planner": {"runner": "codex", "model": "gpt-5.2-codex", "thinking": "max"},
      "implementer": {"runner": "claude", "model": "claude-sonnet-4-5-20250929", "thinking": "standard"},
      "tester": {"runner": "claude", "model": "claude-sonnet-4-5-20250929", "thinking": "standard"},
      "reviewer": {"runner": "codex", "model": "gpt-5.2-codex", "thinking": "max"}
    }
  }]
}
```

**Thinking levels**: `none`, `minimal`, `low`, `standard`, `high`, `max`
- Codex: maps to `-c model_reasoning_effort` (none→xhigh)
- Claude: maps to `MAX_THINKING_TOKENS` env var (0→32000 per request)

See `schema/config.schema.json` for all options.

### Role-Local Delegation (Phase 4 Implementer + Planner Recon Pilot)

Superloop supports loop-level delegation config for nested, role-local orchestration.

- `delegation.enabled`: opt-in switch (default `false`)
- `delegation.dispatch_mode`: `serial | parallel`
- `delegation.wake_policy`: `on_child_complete | on_wave_complete`
- `delegation.max_children`: max delegated children selected from a wave
- `delegation.max_parallel`: optional parallel worker cap alias (defaults to `max_children`)
- `delegation.failure_policy`: `warn_and_continue | fail_role` (default `warn_and_continue`; planner reconnaissance defaults to `fail_role` when policy is unset at loop + role levels)
- `delegation.roles.<role>.mode`: `standard | reconnaissance` (`planner` delegation is forced to `reconnaissance`)
- `delegation.retry_limit`: max retry count per child (default `0`)
- `delegation.retry_backoff_seconds`: base retry backoff (default `0`)
- `delegation.retry_backoff_max_seconds`: max retry backoff cap (default `30`)
- Legacy aliases are accepted for compatibility:
  - `immediate` -> `on_child_complete`
  - `after_all` -> `on_wave_complete`
- Per-role overrides can be set under `delegation.roles.<role>.*`.

Current pilot behavior is intentionally conservative:

- Top-level role order remains sequential.
- Delegation execution is enabled for `implementer` and `planner`; `tester`/`reviewer` remain guardrailed off.
- Planner delegation is reconnaissance-only (read-heavy analysis/synthesis subtasks, no canonical artifact writes).
- Planner reconnaissance enforces serial child dispatch for safer write-guard checks.
- Child execution uses a bounded executor with `serial` and wave-level `parallel` dispatch support.
- `wake_policy=on_child_complete` supports adaptive parent replans for serial and parallel child completions.
- Parallel dispatch uses bounded fan-out (`max_parallel`) with deterministic aggregation, while adaptation decisions can stop remaining queued children/waves.
- Canonical role outputs remain parent-owned.

#### Delegation Request File Contract

Delegated child work is request-driven. Provide one of:

- Iteration-local: `.superloop/loops/<loop-id>/delegation/iter-<n>/<role>/request.json`
- Shared fallback: `.superloop/loops/<loop-id>/delegation/requests/<role>.json`

Request shape:

```json
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "task-a",
          "prompt": "Implement the API endpoint for user search",
          "context_files": ["src/api/users.ts", "src/routes/index.ts"]
        }
      ]
    }
  ]
}
```

Notes:

- `children` can also be provided at top level (treated as one implicit wave).
- If no request file exists, enabled `implementer`/`planner` roles run a delegation-request pass first (`delegation_request_pass_start`/`delegation_request_pass_end`) to author `request.json` for that role turn.
- Bounds are enforced by config (`max_waves`, `max_children`, `max_parallel`, `child_timeout_seconds`, `retry_limit`).
- Child events are emitted as `delegation_child_start` and `delegation_child_end`.
- Scheduler lifecycle emits `delegation_wave_dispatch`, `delegation_wave_queue_drain`, `delegation_wave_start`, and `delegation_wave_end`.
- Wave stop policy checkpoints emit `delegation_policy_decision` with stop reason metadata.
- Child status artifacts include `status` plus canonical `terminal_state` (`completed | failed | timed_out | cancelled | policy_violation | skipped`).
- Planner child prompts include explicit reconnaissance constraints (`mode=reconnaissance`) to keep subtasks read-heavy and bounded.
- Reconnaissance mode now performs a repo write guard around each child run; violations emit `delegation_recon_violation`.
- Recon violations are policy-governed: `failure_policy=warn_and_continue` downgrades child status to `policy_violation`, `failure_policy=fail_role` aborts the role.
- If planner reconnaissance policy is unspecified at both loop and role scopes, Superloop applies a safety default of `fail_role`.
- Adaptive wake emits `delegation_adaptation_start`, `delegation_adaptation_end`, and `delegation_adaptation_skipped` events.
- Adaptation decisions are bounded by per-wave and per-iteration replan limits derived from active delegation bounds.
- `failure_policy=fail_role` aborts the current role turn when delegated child failure is observed (with `delegation_fail_role` event).
- Retry backoff uses bounded exponential delay between child retry attempts.
- Parent role prompts receive delegation status + summary references so the parent can consume child outputs in the same turn.
- Per-role delegation status and summaries are persisted under:
  - `.superloop/loops/<loop-id>/delegation/iter-<n>/<role>/status.json`
  - `.superloop/loops/<loop-id>/delegation/iter-<n>/<role>/summary.md`
- Delegation status includes scheduler contract metadata (`scheduler.state_model`, `scheduler.concurrency_cap`, `scheduler.invariants`, terminal-state counters).
- Adaptive replan artifacts are persisted under:
  - `.superloop/loops/<loop-id>/delegation/iter-<n>/<role>/adaptation/`
- Run summary entries now include per-iteration delegation rollups (`role_entries`, `enabled_roles`, child execution totals, adaptation counters, recon violations, by-role breakdown).
- Timeline lines and `status --summary` output include delegation rollup counters for quick operational inspection.

### RLMS Hybrid Long-Context Mode

When `loops[].rlms.enabled=true`, Superloop can run a bounded REPL-style recursive analyzer before each role:

- `mode=auto`: trigger from context size thresholds.
- `mode=requested`: trigger only when `request_keyword` appears in loop context files.
- `mode=hybrid`: run when either auto or requested trigger is true.
- `policy.fail_mode=warn_and_continue|fail_role`: choose whether RLMS failures are non-fatal or role-fatal.
- `limits.max_subcalls`: cap recursive sub-LLM call count per role execution.
- Root/subcall CLI wiring: by default RLMS inherits the role's resolved runner command/args/model/thinking settings.
- Optional env overrides:
  - `SUPERLOOP_RLMS_ROOT_COMMAND_JSON`, `SUPERLOOP_RLMS_ROOT_ARGS_JSON`, `SUPERLOOP_RLMS_ROOT_PROMPT_MODE`
  - `SUPERLOOP_RLMS_SUBCALL_COMMAND_JSON`, `SUPERLOOP_RLMS_SUBCALL_ARGS_JSON`, `SUPERLOOP_RLMS_SUBCALL_PROMPT_MODE`

Artifacts are written under `.superloop/loops/<loop-id>/rlms/` and linked into prompts, evidence, events, and run summaries.

### RLMS Canary Gate

CI runs a deterministic canary loop (`rlms-canary`) and enforces both status and quality checks using:

- `scripts/assert-rlms-canary.sh`

The script validates:

- `reviewer.status.json`: `status == "ok"` and (optionally) `should_run == true`
- `reviewer.json`: `ok == true`, citation thresholds, non-fallback citation thresholds, and optional highlight regex

Threshold knobs (CLI flags or env vars):

- `RLMS_CANARY_MIN_CITATIONS` (default: `1`)
- `RLMS_CANARY_MIN_NON_FALLBACK_CITATIONS` (default: `1`)
- `RLMS_CANARY_FALLBACK_SIGNALS` (default: `file_reference`)
- `RLMS_CANARY_REQUIRE_HIGHLIGHT_PATTERN` (default in CI: `mock_root_complete`)

### RLMS for New Engineers (No Prior Context Required)

This section explains RLMS from zero context and recaps what is now live in Superloop.

#### 1) What RLMS Means

RLMS stands for Recursive Language Model Scaffold.

In a normal LLM flow, you send one prompt and get one answer.
In RLMS, the model can:

- write small code programs,
- inspect large inputs in pieces,
- call a sub-model recursively on selected chunks,
- and assemble a final answer from those intermediate results.

The practical effect is better handling of long, dense context without requiring all content in one model window.

#### 2) Why Superloop Needed It

Superloop roles often need to analyze large code/spec/test context.
Single-shot prompting is brittle for this.
We needed a system that is:

- bounded (time, depth, steps, subcalls),
- safe (sandbox constraints),
- auditable (artifacts/events),
- and operationally enforced in CI.

#### 3) How RLMS Works in Superloop

At run time, for each role where RLMS is enabled:

1. Superloop gathers role context files.
2. Trigger policy decides whether RLMS should run (`auto`, `requested`, `hybrid`).
3. `scripts/rlms` launches the Python worker.
4. `scripts/rlms_worker.py` runs a sandboxed REPL loop:
   - root command returns Python code,
   - code executes against helper APIs (`list_files`, `read_file`, `grep`, `sub_rlm`, `set_final`),
   - `sub_rlm` can call the configured sub-model command with limits.
5. Worker writes structured output artifacts.
6. Superloop continues with normal role execution, using RLMS artifacts in prompt/evidence/event flow.

#### 4) Safety and Control Limits

RLMS behavior is constrained by loop config:

- `limits.max_steps`
- `limits.max_depth`
- `limits.timeout_seconds`
- `limits.max_subcalls`
- `policy.fail_mode` (`warn_and_continue` or `fail_role`)

Sandbox protections in worker include:

- blocked dangerous AST patterns (imports, dunder access, unsafe constructs),
- restricted builtins and allowed method-call surface,
- bounded subprocess execution for subcalls.

#### 5) Artifacts You Can Inspect

Per loop, RLMS data is written under:

- `.superloop/loops/<loop-id>/rlms/index.json`
- `.superloop/loops/<loop-id>/rlms/latest/<role>.json`
- `.superloop/loops/<loop-id>/rlms/latest/<role>.status.json`
- `.superloop/loops/<loop-id>/rlms/latest/<role>.md`

These are linked into prompt context, evidence outputs, and timeline/event streams.

#### 6) What Is Now CI-Enforced

Superloop includes a deterministic canary loop: `rlms-canary`.

CI job `rlms-canary` in `.github/workflows/ci.yml` does:

1. validate config,
2. run `./superloop.sh run --repo . --loop rlms-canary`,
3. assert status + quality via `scripts/assert-rlms-canary.sh`.

This gate fails PRs if RLMS stops running correctly or quality drops below thresholds.

#### 7) Deterministic CI Setup

To avoid flaky model-dependent CI:

- canary runner is patched to local shell behavior in CI job scope,
- RLMS root/subcall are overridden with deterministic scripts:
  - `scripts/rlms-mock-root.sh`
  - `scripts/rlms-mock-subcall.sh`

This ensures stable pass/fail signals while still testing the Superloop RLMS integration path end-to-end.

For the same deterministic flow locally, run:

- `./scripts/run-local-canary.sh --repo .`

#### 8) Test Coverage

Key tests:

- `tests/rlms.bats` for trigger policy, fallback behavior, artifacts, REPL success/failure limits.
- `tests/rlms-canary-gate.bats` for canary assertion script pass/fail cases.
- `tests/superloop.bats` for loop/config baseline validation including RLMS static checks.

#### 9) Delivery History (High-Level)

RLMS capability evolved in phases:

- initial hybrid integration + artifacts/events/prompts,
- promotion to sandboxed REPL worker,
- sandbox usability fix for safe method calls,
- max-subcalls budget control,
- reusable `rlms-canary` loop,
- CI status + quality canary gate.

#### 10) Current Status and Remaining Work

Completed:

- Workstream 1: CI canary execution gate.
- Workstream 2: quality threshold gate.

Still open (tracked in issue `#9`):

- Workstream 3: fallback strategy for retryable model failures.
- Workstream 4: RLMS budget telemetry in reports.
- Workstream 5: broader sandbox policy regression suite.
- Workstream 6: progressive rollout playbook for real loops.

## Dashboard

Superloop includes a **liquid dashboard** - a contextual UI that adapts to loop state:

```bash
cd packages/superloop-ui
bun run dev
```

Then open `http://localhost:3333/liquid` to see:
- **Automatic views** - UI morphs based on loop phase (planning, implementing, testing, reviewing)
- **Gate status** - Real-time test/approval/checklist status
- **Task progress** - Current phase tasks with completion tracking
- **Cost tracking** - Token usage and cost breakdown

**Custom views via Claude Code:**

```
/superloop-view show me what tests are failing
/superloop-view how much has this cost so far?
```

The `/superloop-view` skill generates custom dashboard views for specific questions.

## Packages

Superloop includes these workspace packages:

- **[json-render-core](packages/json-render-core/)** - Core generative UI schema, validation, and action model.
- **[json-render-react](packages/json-render-react/)** - React renderer for `json-render-core` UITrees.
- **[superloop-ui](packages/superloop-ui/)** - Liquid dashboard and prototype viewer.
- **[superloop-viz](packages/superloop-viz/)** - Visualization package for loop data and artifacts.

## Commands

| Command | Description |
|---------|-------------|
| `init --repo DIR` | Create `.superloop/` scaffolding |
| `run --repo DIR` | Start or resume the loop |
| `run --dry-run` | Read-only status from existing artifacts |
| `run --fast` | Use `runner.fast_args` if configured |
| `status --repo DIR` | Print current state |
| `status --summary` | Print gate/evidence snapshot |
| `usage --loop ID` | Show token usage and cost summary |
| `usage --json` | Machine-readable usage output |
| `approve --loop ID` | Record approval for pending gate |
| `cancel` | Stop and clear state |
| `validate` | Check config against schema |
| `runner-smoke` | Preflight runner auth + compatibility checks |
| `report --loop ID` | Generate HTML report |
| `--version` | Print version |

## Gates

The loop only completes when ALL gates pass:

- **Promise**: Reviewer outputs exact `completion_promise` tag
- **Tests**: All test commands exit 0
- **Checklists**: All `[ ]` items checked `[x]`
- **Evidence**: All artifact files exist (with hash verification)
- **Approval**: Human approval recorded (if enabled)

## Outputs

Each loop writes to `.superloop/loops/<loop-id>/`:

```
plan.md              # Current plan
implementer.md       # Implementation summary
test-report.md       # Test analysis
review.md            # Reviewer assessment
test-status.json     # Pass/fail status
evidence.json        # Artifact hashes
gate-summary.txt     # Gate statuses
events.jsonl         # Event stream
usage.jsonl          # Token usage and cost per role
rlms/                # RLMS index + per-iteration role analysis artifacts
delegation/          # Delegation index + request/summary/child execution artifacts
timeline.md          # Human-readable timeline
report.html          # Visual report (includes usage/cost section)
logs/iter-N/         # Per-iteration logs
```

## Directory Structure

```
superloop/
├── superloop.sh           # Main executable
├── src/                   # Bash modules (12 files)
├── schema/                # Config JSON schema
├── scripts/
│   ├── build.sh           # Assembles src/ into superloop.sh
│   ├── rlms               # RLMS wrapper entrypoint
│   ├── rlms_worker.py     # RLMS recursive analysis worker
│   └── validation/        # Smoke test utilities
├── packages/
│   ├── json-render-core/  # Generative UI framework (catalog, validation, actions)
│   ├── json-render-react/ # React renderer for UITrees
│   ├── superloop-ui/      # Liquid dashboard and prototype viewer
│   └── superloop-viz/     # Visualization tooling for loops and reports
├── .superloop/
│   ├── config.json        # Loop configuration
│   ├── roles/             # Role definitions (planner, implementer, tester, reviewer)
│   └── templates/         # Spec template
└── .claude/skills/        # Claude Code skills (/construct-superloop, /superloop-view)
```

## Development

```bash
# Edit modules
vim src/*.sh

# Rebuild
./scripts/build.sh

# Verify (CI checks this)
git diff --exit-code superloop.sh
```

## Testing

Superloop has comprehensive test coverage across TypeScript packages and bash orchestration:

- **470+ passing tests** (215 BATS + 256 TypeScript)
- **70%+ overall coverage**, 90%+ on critical paths
- **Zero API calls** - all tests use mocks for deterministic, fast execution

```bash
# Run TypeScript tests
cd packages/json-render-core && npm test
cd packages/json-render-react && npm test
cd packages/superloop-ui && npm test

# Run BATS integration tests
bats tests/*.bats

# With coverage
npm run test:coverage
```

See [TESTING.md](TESTING.md) for detailed information on:
- Test structure and organization
- Running tests and generating coverage reports
- Writing new tests
- CI/CD integration

## Design

See [ARCHITECTURE.md](ARCHITECTURE.md) for the rationale behind Superloop's design decisions:
- Why separate roles (Planner, Implementer, Tester, Reviewer)
- Why one phase at a time
- Why gates and the promise system
- Why atomic tasks with checkboxes
- Why spec-driven testing (AC coverage verification)

## Security

See [SECURITY.md](SECURITY.md) for vulnerability reporting and disclosure guidance.

## License

MIT
