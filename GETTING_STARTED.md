# Getting Started with Ralphcodex

Ralphcodex is a Codex CLI wrapper that runs a multi-role loop (planner, implementer, tester, reviewer) with hard gates. The goal is not "more automation" but "reliable completion": every iteration leaves behind a trail of artifacts that prove the work is done (or show exactly why it is not).

## Philosophy

Ralphcodex treats software work as a controlled loop instead of a single pass.

- Explicit intent beats implicit intent: a written spec is the source of truth.
- Separation of roles reduces blind spots: planner vs implementer vs tester vs reviewer.
- Evidence over assertion: completion requires artifacts, test results, and checklists.
- Minimal churn: unchanged plans/reports should stay unchanged to preserve signal.
- Humans stay in the loop when it matters: optional approval gates.

## Core mechanisms

### Roles

Each role has a narrow responsibility and a single output file:

- Planner: keeps the plan aligned with the spec.
- Implementer: changes code and summarizes changes.
- Tester: summarizes test status and gaps.
- Reviewer: verifies against spec + gates, emits the promise.

### Gates

A loop only completes when all gates are green:

- Promise: reviewer emits `<promise>READY</promise>` (exact match to `completion_promise`).
- Tests: pass (either every iteration or on-promise).
- Checklists: all items are complete.
- Evidence: required artifacts exist (and are tracked with hashes/mtimes).
- Approval (optional): a human explicitly approves completion.

### Iteration artifacts

Each iteration writes artifacts under `.ralph/loops/<loop-id>/`:

- Plan, reports, test output, checklist status.
- Gate summary and evidence manifest.
- Events and timeline for observability.
- `report.html` summarizing a run.

### Safety controls

- Stuck detection: stop after N no-progress iterations.
- Per-role timeouts: terminate long/hung roles cleanly.
- Reviewer packet: a condensed context bundle for the reviewer.

## Minimal workflow

1) Initialize `.ralph` in your repo:

```bash
./ralph-codex.sh init --repo /path/to/repo
```

2) Write the spec:

```
/path/to/repo/.ralph/spec.md
```

3) Create a checklist file in your repo.

4) Configure the loop in `.ralph/config.json`.

5) Run the loop:

```bash
./ralph-codex.sh run --repo /path/to/repo
```

6) If approval is required:

```bash
./ralph-codex.sh approve --repo /path/to/repo --loop <loop-id>
```

7) Generate an HTML report:

```bash
./ralph-codex.sh report --repo /path/to/repo --loop <loop-id>
```

## Tutorial: Log summarizer (more than hello world)

This tutorial builds a small but real feature: a CLI that summarizes a log file, with tests, sample data, and documentation.

### 1) Create a scratch repo

```bash
mkdir ralph-demo
cd ralph-demo
git init
```

### 2) Initialize Ralphcodex

```bash
/path/to/ralph-codex/ralph-codex.sh init --repo .
```

### 3) Write the spec

Replace `.ralph/spec.md` with the following:

```md
# Log Summarizer

Goal:
- Build a CLI tool that summarizes log files by level and error code.

Requirements:
1) Implement `logsum.py` with CLI usage: `python logsum.py <path>`.
2) Output must include:
   - total lines
   - counts per level (INFO, WARN, ERROR)
   - top 3 error codes (e.g., E100, E205)
3) Add `samples/app.log` with at least 30 lines and multiple levels/codes.
4) Add tests under `tests/` using `python -m unittest`.
5) Update `README.md` with usage and example output.

Completion promise: READY
```

### 4) Create a checklist

Create `CHECKLIST.md`:

```md
- [ ] logsum.py implements required output fields
- [ ] sample log file is present and referenced in README
- [ ] tests run with `python -m unittest`
- [ ] README includes usage + example output
```

### 5) Configure the loop

Edit `.ralph/config.json` to point to your spec and checklist:

```json
{
  "codex": {
    "args": ["--full-auto"],
    "fast_args": ["--full-auto", "-c", "model_reasoning_effort=\"low\""]
  },
  "loops": [
    {
      "id": "logsum",
      "spec_file": ".ralph/spec.md",
      "max_iterations": 10,
      "completion_promise": "READY",
      "checklists": ["CHECKLIST.md"],
      "tests": {
        "mode": "on_promise",
        "commands": ["python -m unittest"]
      },
      "evidence": {
        "enabled": true,
        "require_on_completion": true,
        "artifacts": ["logsum.py", "tests", "samples/app.log", "README.md"]
      },
      "approval": {
        "enabled": true,
        "require_on_completion": true
      },
      "reviewer_packet": {
        "enabled": true
      },
      "timeouts": {
        "enabled": true,
        "default": 900,
        "planner": 300,
        "implementer": 900,
        "tester": 300,
        "reviewer": 1200
      },
      "stuck": {
        "enabled": true,
        "threshold": 3,
        "action": "report_and_stop",
        "ignore": [
          ".ralph/**",
          ".git/**",
          "node_modules/**",
          "dist/**",
          "build/**",
          "coverage/**",
          ".next/**",
          ".venv/**",
          ".tox/**",
          ".cache/**"
        ]
      },
      "roles": ["planner", "implementer", "tester", "reviewer"]
    }
  ]
}
```

### 6) Run the loop

```bash
/path/to/ralph-codex/ralph-codex.sh run --repo . --loop logsum
```

If it pauses for approval:

```bash
/path/to/ralph-codex/ralph-codex.sh approve --repo . --loop logsum
```

### 7) Inspect results

Artifacts live here:

```
.ralph/loops/logsum/
```

Key files to check:

- `review.md` for the completion promise and final review.
- `test-report.md` and `test-output.txt` for test results.
- `evidence.json` for artifact hashes and proof of completion.
- `report.html` for a consolidated timeline.

### 8) Iterate or tighten gates

If the reviewer is too lenient, tighten the spec or checklist. If the plan churns, check whether the spec is vague. If tests are slow, move to `on_promise` mode and rely on checklists + evidence during iterations.

## Troubleshooting

- "Approval pending": run `ralph-codex.sh approve`.
- "Stuck detected": inspect `stuck-report.md`, then refine spec or checklist.
- "Plan churn": clarify spec and reduce ambiguity.
- "Reviewer mismatch": ensure the reviewer promise exactly matches `completion_promise`.

## Next steps

- Add multiple loops for phased delivery (e.g., design phase vs implementation phase).
- Use `status --summary` and `report` to build lightweight audits.
- Create tighter evidence lists so completion is provable, not just asserted.
