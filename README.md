# Ralph++ Codex Wrapper

This is a Codex CLI wrapper that runs a multi-role Ralph-style loop (planner, implementer, tester, reviewer) with enforced gates for checklists and tests.

## Quick start

1) Initialize `.ralph` in your repo:

```bash
/Users/multiplicity/Work/ralph-codex/ralph-codex.sh init --repo /path/to/repo
```

2) Edit the spec:

```
/path/to/repo/.ralph/spec.md
```

3) Configure loops, tests, and checklists:

```
/path/to/repo/.ralph/config.json
```

4) Run the loop:

```bash
/Users/multiplicity/Work/ralph-codex/ralph-codex.sh run --repo /path/to/repo
```

## Config overview

`.ralph/config.json` controls the loop. Example:

```json
{
  "codex": {
    "args": ["--full-auto"],
    "fast_args": ["--full-auto", "--model", "gpt-5.2-codex"]
  },
  "loops": [
    {
      "id": "initiation",
      "spec_file": ".ralph/spec.md",
      "max_iterations": 20,
      "completion_promise": "INITIATION_READY",
      "checklists": ["feat/my-feature/initiation/tasks/PHASE_1.MD"],
      "tests": {
        "mode": "on_promise",
        "commands": ["npm test"]
      },
      "evidence": {
        "enabled": true,
        "require_on_completion": true,
        "artifacts": ["README.md", "src/index.ts"]
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

## Outputs

Each loop writes to:

```
.ralph/loops/<loop-id>/
  plan.md
  iteration_notes.md
  implementer.md
  review.md
  test-output.txt
  test-status.json
  checklist-status.json
  checklist-remaining.md
  gate-summary.txt
  last_messages/
  logs/iter-N/
```

## Commands

- `init`: Create `.ralph/` scaffolding.
- `run`: Start or resume the loop.
- `status`: Print `.ralph/state.json`.
- `cancel`: Remove `.ralph/state.json`.
- `run --fast`: Use `codex.fast_args` if provided (falls back to `codex.args`).
- `run --dry-run`: Run planner+reviewer only for a quick status check without writing state or gate artifacts.
- `self-check.sh --repo DIR --loop ID [--fast]`: Run a churn smoke check (two consecutive runs must leave plan/report files unchanged).

## Notes

- The loop only completes when the reviewer outputs the exact promise AND all gates pass.
- Tests can run `every` iteration or only `on_promise` (default).
- Checklist validation ignores code blocks and treats missing files as failures.
- In `on_promise` mode, tests also run once checklists are complete to avoid deadlock.
- The tester writes `test-report.md` and the reviewer writes `review.md` each iteration.
- Gate summaries are written to `gate-summary.txt` each iteration (promise/tests/checklists/evidence/stuck).
- Anti-churn: role prompts discourage unnecessary edits, and the wrapper restores plan/report files when content is unchanged to avoid rewrite noise.
- Evidence manifests are written to `evidence.json` when enabled; optional artifact hashes can be enforced on completion.
- Stuck detection stops the loop after a configurable number of no-progress iterations and writes `stuck-report.md`.
