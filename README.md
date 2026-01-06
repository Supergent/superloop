# Supergent Runner Wrapper

This is a runner-driven CLI wrapper that runs a multi-role loop (planner, implementer, tester, reviewer) with enforced gates for checklists and tests.

## Quick start

1) Initialize `.superloop` in your repo:

```bash
/Users/multiplicity/Work/ralph-codex/superloop.sh init --repo /path/to/repo
```

2) Edit the spec:

```
/path/to/repo/.superloop/spec.md
```

3) Configure loops, tests, and checklists:

```
/path/to/repo/.superloop/config.json
```

4) Run the loop:

```bash
/Users/multiplicity/Work/ralph-codex/superloop.sh run --repo /path/to/repo
```

For philosophy, principles, and a deeper tutorial, see `GETTING_STARTED.md`.

Note: the legacy `.ralph/` workspace is deprecated. Use `.superloop/` only; if you still have `.ralph/`, migrate manually by re-initializing and copying the spec/config, then remove `.ralph/` once verified.

## Config overview

`.superloop/config.json` controls the loop and runner (examples use `codex exec`). Example:

```json
{
  "runner": {
    "command": ["codex", "exec"],
    "args": ["--full-auto", "-C", "{repo}", "--output-last-message", "{last_message_file}", "-"],
    "fast_args": ["--full-auto", "-c", "model_reasoning_effort=\"low\"", "-C", "{repo}", "--output-last-message", "{last_message_file}", "-"],
    "prompt_mode": "stdin"
  },
  "loops": [
    {
      "id": "initiation",
      "spec_file": ".superloop/spec.md",
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
      "approval": {
        "enabled": false,
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
          ".superloop/**",
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
.superloop/loops/<loop-id>/
  plan.md
  iteration_notes.md
  implementer.md
  review.md
  test-output.txt
  test-status.json
  checklist-status.json
  checklist-remaining.md
  evidence.json
  reviewer-packet.md
  approval.json
  gate-summary.txt
  events.jsonl
  decisions.jsonl
  decisions.md
  run-summary.json
  timeline.md
  report.html
  last_messages/
  logs/iter-N/
```

## Commands

- `init`: Create `.superloop/` scaffolding.
- `run`: Start or resume the loop.
- `status`: Print `.superloop/state.json`.
- `approve`: Record an approval or rejection for a pending approval gate.
- `cancel`: Remove `.superloop/state.json`.
- `run --fast`: Use `runner.fast_args` if provided (falls back to `runner.args`).
- `run --dry-run`: Read-only status summary from existing artifacts; no runner calls.
- `status --summary`: Print latest gate/evidence snapshot from `run-summary.json` (use `--loop` to pick a loop).
- `validate`: Validate a config file against `schema/config.schema.json`.
- `report`: Generate an HTML report from loop artifacts (events, summary, timeline).
- `report --out FILE`: Write the report to a custom path.
- `--version`: Print the current wrapper version.
- `self-check.sh --repo DIR --loop ID [--fast]`: Run a churn smoke check (two consecutive runs must leave plan/report files unchanged).

## Notes

- The loop only completes when the reviewer outputs the exact promise AND all gates pass.
- Tests can run `every` iteration or only `on_promise` (default).
- Checklist validation ignores code blocks and treats missing files as failures.
- In `on_promise` mode, tests also run once checklists are complete to avoid deadlock.
- The tester writes `test-report.md` and the reviewer writes `review.md` each iteration.
- Gate summaries are written to `gate-summary.txt` each iteration (promise/tests/checklists/evidence/stuck).
- Anti-churn: role prompts discourage unnecessary edits, and the wrapper restores plan/report files when content is unchanged to avoid rewrite noise.
- Evidence manifests are written to `evidence.json` when enabled and include artifact hashes/mtimes and gate-produced file metadata.
- Reviewer packets are written to `reviewer-packet.md` when enabled to summarize gates, tests, checklists, and evidence for the reviewer.
- Optional per-role timeouts can stop a run if a role exceeds the configured limit.
- Optional approval gating can pause completion until a human approves (records decisions in `decisions.jsonl`/`decisions.md`).
- Stuck detection stops the loop after a configurable number of no-progress iterations and writes `stuck-report.md`.
- Runner prompt mode controls whether prompts are piped via stdin or provided as a file.
- Runner args support `{repo}`, `{prompt_file}`, and `{last_message_file}` placeholders.

## Development

- Edit `src/*.sh` and run `scripts/build.sh` to regenerate `superloop.sh`.
- CI checks that the generated `superloop.sh` is up to date.
