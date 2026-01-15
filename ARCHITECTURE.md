# Superloop Architecture

This document explains the **why** behind Superloop's design decisions.

## Core Principle: Controlled Autonomy

AI agents are powerful but unpredictable. Superloop provides structure that channels that power toward reliable completion:

- **Separation of concerns** - different roles for different cognitive tasks
- **Hard gates** - objective completion criteria, not vibes
- **Incremental progress** - observable, resumable, debuggable
- **Human control points** - spec authoring, approval gates, stuck escalation

## Why Separate Roles?

```
Planner → Implementer → Tester → Reviewer
```

**Not one agent doing everything.** Each role has one job:

| Role | Cognitive Mode | Why Separate |
|------|----------------|--------------|
| Planner | Strategic thinking | Planning and coding are different skills |
| Implementer | Tactical execution | Focused on tasks, not judging completeness |
| Tester | Adversarial analysis | Fresh eyes find bugs the author missed |
| Reviewer | Judgment | Can't mark your own work complete |

**Benefits:**
- Debuggability - when something fails, you know which role failed
- Swappable models - use Opus for planning, Sonnet for implementation
- Prevents conflicts - implementer can't approve own code
- Fresh perspective - reviewer sees work without implementation bias

## Why Spec vs Plan?

```
spec.md (human) → PLAN.MD (Planner) → PHASE_*.MD (Planner)
```

**Separation of WHAT from HOW:**

| Artifact | Author | Contains | Stability |
|----------|--------|----------|-----------|
| spec.md | Human | Requirements, acceptance criteria | Fixed during loop |
| PLAN.MD | Planner | Architecture, phases overview | Rarely changes |
| PHASE_*.MD | Planner | Atomic tasks with checkboxes | Created incrementally |

**Why this matters:**
- Human controls scope (spec), AI controls execution (plan)
- If wrong thing built → check spec
- If built wrong → check plan
- Clear accountability

## Why One Phase at a Time?

The Planner might outline 5 phases in PLAN.MD, but only creates PHASE_1.MD initially. PHASE_2.MD is created only when PHASE_1.MD is complete.

**Rationale:**

1. **Reality changes plans.** By iteration 5, the Planner has seen what actually worked, what broke, what the codebase looks like after changes. Phase 2's tasks would be different than if planned upfront.

2. **Prevents wasted work.** If you detail 50 tasks across 5 phases and Phase 1 reveals an architecture problem, you throw away 40 tasks.

3. **Context window economics.** Detailed PHASE files are long. Creating all upfront means larger payloads, more tokens, more noise.

4. **Mirrors human workflow.** You don't write detailed tickets for Phase 5 before Phase 1 is done. Sketch the roadmap, detail the immediate work.

**The tradeoff:** Less predictability upfront. But better plans that adapt to reality.

## Why Gates?

The loop only completes when ALL gates pass:

```
Promise    - Reviewer explicitly declares completion
Tests      - Automated verification passes
Checklists - Manual verification items checked
Evidence   - Required artifacts exist (with hashes)
Approval   - Human sign-off (when enabled)
```

**Why not just "AI says it's done"?**

- **Objective criteria** - "done" is verifiable, not subjective
- **Prevents premature completion** - can't skip testing
- **Evidence trail** - proof that work happened
- **Multiple verification** - defense in depth
- **Human oversight** - approval gate when stakes are high

## Why the Promise System?

```xml
<promise>SUPERLOOP_COMPLETE</promise>
```

Only the Reviewer can emit this. The loop continues until it appears AND all gates pass.

**Rationale:**
- **Explicit signal** - Reviewer must consciously declare completion
- **Prevents accidents** - can't complete by mistake
- **Separation of concerns** - Implementer can't self-approve
- **Verifiable** - simple string match, no ambiguity

## Why Conservative Planner?

The Planner follows these rules:
- If PHASE has unchecked tasks → do nothing
- Only create next PHASE when current is complete
- Only update PLAN.MD if scope/architecture must change

**Rationale:**
- **Churn prevention** - don't rewrite what's working
- **Stability** - plan doesn't thrash between iterations
- **Focus** - Implementer works on tasks, not re-reading changed plans
- **Debugging** - if plan changes, it's for a reason

## Why Atomic Tasks?

```markdown
## P1.2 API Setup
1. [ ] Create `src/api/users.ts` with GET /users endpoint
2. [ ] Add auth middleware to `src/middleware/auth.ts`
   1. [ ] Implement JWT validation
   2. [ ] Add role-based access check
```

**Rationale:**
- **Progress tracking** - see exactly where things are
- **Resumability** - if interrupted, know where to continue
- **Verifiability** - each task small enough to verify
- **Debugging** - if something breaks, find which task caused it
- **File paths included** - no ambiguity about where code goes

## Why Tester as Separate Role?

The Tester doesn't just run tests - it analyzes results:

```
Automated tests → Tester reads output → test-report.md
                  Tester explores UI → findings
                  Tester identifies gaps → recommendations
```

**Rationale:**
- **Analysis, not just execution** - understands WHY tests failed
- **Exploratory testing** - catches things automated tests miss
- **Reporting** - provides human-readable assessment
- **Browser exploration** - can manually test UI when enabled

## Why Stuck Detection?

If no file changes for N consecutive iterations, the loop stops and writes `stuck-report.md`.

**Rationale:**
- **Prevents infinite loops** - some problems can't be solved by iteration
- **Resource protection** - don't burn API credits on stuck loops
- **Debugging signal** - stuck report explains what's wrong
- **Human escalation** - some problems need human intervention

## Why Iterative Loop?

```
Iteration 1: Planner → Implementer → Tester → Reviewer (not done)
Iteration 2: Planner → Implementer → Tester → Reviewer (not done)
Iteration 3: Planner → Implementer → Tester → Reviewer (done!)
```

**Why not single-shot?**

- Complex features can't be done in one pass
- Test failures need fixing
- Reviewer feedback needs addressing
- Incremental progress is observable
- Can resume after interruption (rate limits, crashes)

## Summary

Superloop's design optimizes for:

| Goal | Mechanism |
|------|-----------|
| Reliability | Hard gates, multiple verification |
| Debuggability | Separate roles, atomic tasks, event logs |
| Adaptability | Incremental phases, conservative updates |
| Human control | Spec authoring, approval gates, stuck escalation |
| Efficiency | One phase at a time, minimal churn |

The complexity exists to make AI agents **reliably useful**, not just impressively autonomous.
