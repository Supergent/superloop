# Feature: Boolean Default Hardening

## Goal
Eliminate boolean default coercion bugs where explicit `false` values were treated as fallback defaults (especially `// true`).

## Scope
- Add a shared boolean normalizer helper in `src/00-header.sh`.
- Replace vulnerable boolean reads in `src/60-commands.sh` and `src/56-validate-static.sh`.
- Add regression tests in `tests/superloop.bats` and `tests/rlms.bats`.
- Regenerate `superloop.sh` with `scripts/build.sh`.

## Non-Goals (this iteration)
- Changing lifecycle audit policy thresholds or cleanup behavior.
- Refactoring all config reads to shared typed accessors.

## Primary References
- `src/00-header.sh` - shared utility helpers.
- `src/56-validate-static.sh` - static lifecycle gate validation path.
- `src/60-commands.sh` - runtime state/lifecycle/rlms boolean decisions.
- `tests/superloop.bats` - run and validation regressions.
- `tests/rlms.bats` - RLMS role toggle regression.

## Architecture
Use a single helper (`bool_or_default`) to normalize raw boolean reads (`true`/`false`) while only applying defaults for missing/invalid values.

## Decisions
- Keep defaulting behavior intact for missing values, but preserve explicit `false`.
- Replace all runtime/static `// true` boolean reads in source to remove this bug class.
- Assert behavior with both config-level and runtime-level regressions.

## Risks / Constraints
- Large shell test suite runtime; use targeted bats filters for fast confidence.
- Generated `superloop.sh` must be rebuilt after source edits.

## Gate Baseline
- Tests mode: `disabled` in added run-path test loops.
- Validation require on completion: unchanged from existing test fixtures.
- Validation checklist mapping file: `N/A`.

## Phases
- **Phase 1**: implement helper, patch callsites, add regressions, and validate with targeted bats runs.
