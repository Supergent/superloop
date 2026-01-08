# Superloop UI Prototyping Framework

Superloop UI is a rapid prototyping toolkit that treats ASCII mockups as the single source of truth and renders them across web, CLI, and TUI surfaces.

## Quick start

```bash
# From the repo root
cd packages/superloop-ui
bun install
bun run dev
```

In another terminal, create a prototype:

```bash
bun run src/cli.ts generate workgrid
```

## CLI commands

- `superloop-ui generate <view>`: Create a new prototype version in `.superloop/ui/prototypes/<view>/`.
- `superloop-ui refine <view>`: Clone the latest version to a new timestamped file.
- `superloop-ui list`: List existing prototypes and versions.
- `superloop-ui render <view> --renderer cli|tui`: Render a prototype in the terminal.
- `superloop-ui dev`: Launch the WorkGrid web UI with live refresh.
- `superloop-ui export <view>`: Export a simple HTML/CSS scaffold with the rendered ASCII.

## File conventions

- Prototypes live under `.superloop/ui/prototypes/<view-name>/`.
- Single-file prototypes at `.superloop/ui/prototypes/<view-name>.txt` are also supported.
- Each version is a timestamped `.txt` file, for example `20240102-154233.txt`.
- Optional metadata is stored in `meta.json` inside the view directory.
- Use ASCII only (no Unicode box drawing) for max compatibility.

## Data bindings

Inject Superloop loop data into mockups with moustache bindings:

```
Iteration: {{iteration}}
Tests: {{test_status}}
Promise: {{promise}}
```

Bindings are populated from `.superloop/loops/<id>/run-summary.json` when available.

## Prompting Claude Code

When asking Claude Code to generate a mockup, be explicit about the view name,
ASCII-only constraints, and the save location.

Example prompt:

```
Generate a TUI mockup for the WorkGrid view.
Constraints:
- ASCII only (no Unicode box drawing).
- 80x24 minimum, 120x40 maximum.
- Include placeholders like {{iteration}} and {{test_status}}.
Output:
- Save to .superloop/ui/prototypes/workgrid/<timestamp>.txt
```

See `docs/ai-prompting.md` for more prompt templates and guardrails.
