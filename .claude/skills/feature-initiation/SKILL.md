---
name: feature-initiation
description: |
  Enforces feature initiation workflow and branch/worktree hygiene for new feature work.
  Use when starting new feature implementation, creating plans/tasks, or validating issue metadata.
  Triggers: "feature initiation", "new feature", "initiation", "worktree", "feat/<name>/initiation"
---

# Feature Initiation Workflow

This skill is runner-agnostic and applies equally to Claude Code and Codex.

## Purpose

Ensure new feature work starts with explicit scope, auditable artifacts, and isolated branches/worktrees.

## Required for New Feature Work

Before implementation:

1. Create a branch: `feat/<feature-name>/initiation`.
2. Create `feat/<feature-name>/initiation/PLAN.MD`.
3. Create `feat/<feature-name>/initiation/tasks/PHASE_1.MD`.
4. Ensure issue metadata includes:
   - Feature Path
   - Branch
   - Scope
   - Related PRs

## Shared Machine Protocol

When workspace ownership is unclear or checkout is dirty:

1. Do not modify that checkout.
2. Use a dedicated worktree.
3. Implement only in the isolated worktree branch.

## Follow-On Work

After initiation, use:

- `feat/<feature-name>/<meaningful-slug>`

Keep the same `PLAN.MD` + `tasks/PHASE_*.MD` structure for follow-on scoped work.

## Task File Quality

Task lists should be numbered, atomic, and checkable.

- Include concrete file paths for implementation tasks.
- Include a validation section with explicit checks.
- Avoid placeholder/template text in committed phase files.

## Authoring Guidance

When constructing specs/config for loops:

- Keep scope and non-goals explicit.
- Align loop checks with plan artifacts and validation expectations.
- Do not start coding paths before initiation artifacts exist.
