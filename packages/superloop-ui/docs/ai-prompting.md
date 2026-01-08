# AI Prompting Guide for ASCII Mockups

Use this guide when asking Claude Code to generate ASCII UI mockups.

## File targets

- Save files to `.superloop/ui/prototypes/<view-name>/`.
- Use a timestamped filename like `YYYYMMDD-HHMMSS.txt`.
- Single-file prototypes at `.superloop/ui/prototypes/<view-name>.txt` are also supported for quick experiments.
- Keep the content ASCII-only (no Unicode box drawing).

## Prompt template

```
Generate an ASCII mockup for the <view-name> view.
Constraints:
- 80x24 minimum, 120x40 maximum.
- ASCII only (no Unicode box drawing).
- Include placeholders like {{iteration}} and {{test_status}}.
- Use clear labels, frames, and spacing for readability.
Output:
- Save to .superloop/ui/prototypes/<view-name>/<timestamp>.txt
```

## Tips

- Prefer simple borders using +, -, and | characters.
- Keep wide sections under 100 columns.
- Use placeholders consistently so bindings can populate data.
- Include key metadata in the header of the mockup.

## Example snippet

```
+----------------------------------------------+
| RUN SUMMARY                                   |
| Iteration: {{iteration}}                      |
| Tests: {{test_status}}                        |
+----------------------------------------------+
```
