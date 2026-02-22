# Ops Manager V0 Contract (Superloop + Sprites)

## Purpose
This document defines the V0 manager/runtime contract for operating Superloop runs from outside a Sprite sandbox VM.

Primary managed unit:
- `Loop Run`

Default isolation policy:
- one loop run per sprite VM

## Contract Surfaces
V0 exports two envelope types described by `schema/ops-manager.contract.schema.json`:

1. `loop_run_snapshot`
- point-in-time lifecycle projection for one loop id
- includes run identity, manager health signals, and artifact metadata

2. `loop_run_event`
- incremental event envelope from `.superloop/loops/<loop>/events.jsonl`
- cursor-aware, supports polling without event duplication

## Required Runtime Artifacts
Required for V0 snapshot/event ingestion:

- `.superloop/loops/<loop>/events.jsonl`

Optional but consumed when present:

- `.superloop/loops/<loop>/run-summary.json`
- `.superloop/state.json`
- `.superloop/active-run.json`
- `.superloop/loops/<loop>/approval.json`

Adapter scripts fail closed when required artifacts are missing.

## Adapter Commands

### Snapshot
```bash
scripts/ops-manager-loop-run-snapshot.sh \
  --repo /path/to/repo \
  --loop my-loop
```

Options:
- `--run-id <id>`: override inferred run id
- `--pretty`: formatted JSON output

### Incremental Events
```bash
scripts/ops-manager-poll-events.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --cursor-file /tmp/my-loop.cursor.json
```

Options:
- `--from-start`: ignore existing cursor and replay from first event
- `--max-events <n>`: cap events emitted in one poll

## Compatibility and Versioning Rules
- `schemaVersion` is required and currently fixed to `v1`.
- New fields may be added only as backward-compatible additions.
- Breaking changes require a new schema version and dual-read support during migration.
- Manager logic must key off explicit lifecycle fields and not parse free-form text output.

## Failure Behavior
The adapters are intentionally fail-closed for contract safety:

- missing required artifact root or required event file: non-zero exit
- invalid JSON in source artifacts: non-zero exit
- cursor offset ahead of available events: non-zero exit (explicit reset required)

## Operator Notes
- Use snapshot for current lifecycle state.
- Use event polling for real-time progression.
- Use both together to detect divergence between runtime activity and summary state.
