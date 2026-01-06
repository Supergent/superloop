# OpenProse integration (draft)

This repository currently includes a local clone of OpenProse at `prose/`. OpenProse is a
specification, not an executable runtime, so this integration relies on the runner to follow
`prose/skills/open-prose/prose.md` when asked to execute a `.prose` program.

What this enables
- OpenProse control flow inside a single Supergent role run.
- Supergent gates (tests, checklists, evidence, approvals) around the OpenProse workflow.

Minimal setup
1) Use the Prose Author role at `.superloop/roles/prose-author.md` to generate a workflow.
2) Use the OpenProse role at `.superloop/roles/openprose.md` to execute the workflow.
3) In `.superloop/config.json`, include `prose-author` and `openprose` in the `roles` list,
   with `openprose` immediately after `prose-author`. Keep `reviewer` so completion still
   uses a promise gate.
4) The Prose Author writes the program to `.superloop/workflows/openprose.prose`.

Example roles list
```
"roles": ["planner", "prose-author", "openprose", "tester", "reviewer"]
```

Notes
- This uses `prose/skills/open-prose/prose.md` for execution semantics; it does not implement
  OpenProse boot or telemetry.
- The OpenProse role spawns one runner invocation per `session` statement (real sub-sessions).
- Current interpreter supports a minimal subset: `agent`, `session`, `parallel` (inline sessions),
  and simple `context:` lists with single-line prompts.
- If `prose/` is not present, clone it alongside this repo or adjust the role template path.
