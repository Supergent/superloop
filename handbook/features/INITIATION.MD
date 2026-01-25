# Feature Initiation Workflow (Superloop)

This workflow defines the **required** steps for initiating new feature work in the Superloop repo.
It ensures every feature has a clear, traceable path from idea → plan → execution → merge.

## 1) Branching + Worktree (Required)

- **Worktree required**: create a dedicated worktree for the feature branch and do all work there.
- **Branch naming**: `feat/<feature-name>/<slug>`
- **Slug rules**:
  - First pass MUST use `initiation` (reserved).
  - Follow-on work uses a meaningful slug (e.g., `phase-two-routing`).

**Examples**
- `feat/environment-matrix/initiation`
- `feat/environment-matrix/billing-expansion`

## 2) Feature Folder Structure (Required)

Create a new directory at repo root:

```
feat/
└── <feature-name>/
    └── <slug>/
        ├── PLAN.MD
        └── tasks/
            ├── PHASE_1.MD
            ├── PHASE_2.MD
            └── ...
```

- The `initiation/` folder captures the first end-to-end pass.
- Later iterations use a meaningful slug with the same structure.

## 3) PLAN.MD (Required)

`feat/<feature-name>/<slug>/PLAN.MD` is the **blueprint** for the feature:

- **Goal**: one clear sentence
- **Scope**: what is included
- **Non-goals**: what is excluded (this iteration)
- **Primary references**: key files, diagrams, or docs
- **Architecture**: high-level structure
- **Decisions**: key choices + rationale
- **Risks / constraints**: known limits
- **Phases**: high-level phases (Phase 1, Phase 2, ...)

Template: `handbook/features/templates/PLAN.MD`

## 4) Task Decomposition (Required)

Each phase gets a dedicated file in `tasks/`:

- `PHASE_1.MD`, `PHASE_2.MD`, ...
- Tasks must be **atomic**, **checkable**, and **numbered** (P1.x style).

**Example**

```markdown
### P1.3 SSH Helper Worker (`src/index.ts`)

1. [ ] Create `src/index.ts` within `packages/cloudflare-carolina-ssh-helper`.
2. [ ] Implement an HTTP server using `itty-router` (or similar).
3. [ ] Define a `POST /execute-ssh-command` endpoint.
4. [ ] **Authentication Middleware**:
   1. [ ] Read shared secret from `X-SSH-Helper-Secret` header.
   2. [ ] Validate against `env.CAROLINA_SSH_HELPER_SECRET`.
   3. [ ] Return `401 Unauthorized` if validation fails.
```

Template: `handbook/features/templates/PHASE_1.MD`

## 5) Issue Discipline (Required)

We use GitHub Issues as the living handoff for the current iteration.

**Before opening the initiation PR**:
- Create the branch and add `PLAN.MD` + `tasks/PHASE_*.MD` **first**, so issue links resolve.
- Create the GitHub issue **before** opening the initiation PR.

**Issue must include**:
- **Feature Path**: `feat/<feature-name>/<slug>/`
- **Branch**: `feat/<feature-name>/<slug>`
- **Scope**: checkboxes that link to each phase file
  - `feat/<feature-name>/<slug>/tasks/PHASE_1.MD`
  - `feat/<feature-name>/<slug>/tasks/PHASE_2.MD`
  - etc.
- **Related PRs**: list links; include the initiation PR first

**PR body must include**:
- `Closes #<issue>` or `Refs #<issue>`

Automation expects issue scope to match phase files on PRs.

## 6) Optional Scaffolding

Use the helper script to scaffold the initiation structure:

```bash
scripts/init-feature.sh <feature-name> [slug]
```

- `slug` defaults to `initiation`
- Copies templates for `PLAN.MD` and `PHASE_1.MD`
- Prints the issue checklist snippet

## 7) Lifecycle Summary (0 → Main)

Idea → `PLAN.MD` → `PHASE_*.MD` tasks → execution → PRs → merge to `main`

The `feat/<feature-name>/` folder is retained as the permanent record.
