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

`.superloop/config.json` controls runners and loops:

```json
{
  "runner": {
    "command": ["codex", "exec"],
    "args": ["--full-auto", "-C", "{repo}", "-"],
    "prompt_mode": "stdin"
  },
  "loops": [{
    "id": "my-feature",
    "spec_file": ".superloop/specs/my-feature.md",
    "completion_promise": "READY",
    "max_iterations": 20,
    "tests": {
      "mode": "on_promise",
      "commands": ["npm test"]
    },
    "roles": ["planner", "implementer", "tester", "reviewer"]
  }]
}
```

See `schema/config.schema.json` for the full schema.

## Commands

| Command | Description |
|---------|-------------|
| `init --repo DIR` | Create `.superloop/` scaffolding |
| `run --repo DIR` | Start or resume the loop |
| `run --dry-run` | Read-only status from existing artifacts |
| `run --fast` | Use `runner.fast_args` if configured |
| `status --repo DIR` | Print current state |
| `status --summary` | Print gate/evidence snapshot |
| `approve --loop ID` | Record approval for pending gate |
| `cancel` | Stop and clear state |
| `validate` | Check config against schema |
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
timeline.md          # Human-readable timeline
report.html          # Visual report
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
│   └── validation/        # Smoke test utilities
├── packages/superloop-ui/ # UI framework (TypeScript/React)
├── .superloop/
│   ├── config.json        # Loop configuration
│   ├── roles/             # Role definitions (planner, implementer, tester, reviewer)
│   └── templates/         # Spec template
└── .claude/skills/        # Claude Code skills (/construct-superloop)
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

## Design

See [ARCHITECTURE.md](ARCHITECTURE.md) for the rationale behind Superloop's design decisions:
- Why separate roles (Planner, Implementer, Tester, Reviewer)
- Why one phase at a time
- Why gates and the promise system
- Why atomic tasks with checkboxes
- Why spec-driven testing (AC coverage verification)

## License

MIT
