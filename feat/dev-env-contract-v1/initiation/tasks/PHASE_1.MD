# Phase 1 - Contract v1 And Constructor Alignment

## P1.1 Contract Specification

1. [ ] Add a contract document in `docs/` defining canonical env keys and meanings.
2. [ ] Define strict resolution order (canonical -> legacy/product-specific -> generic -> explicit fallback).
3. [ ] Document approved localhost fallback exceptions and when they are allowed.

## P1.2 Constructor Skill Integration

1. [ ] Update `.claude/skills/construct-superloop/SKILL.md` to require contract awareness during loop construction.
2. [ ] Ensure the skill explicitly states runner parity for Claude Code and Codex in contract handling guidance.
3. [ ] Ensure skill references to companion skills remain current and non-contradictory.

## P1.3 Local Dev Skill Alignment

1. [ ] Update `.claude/skills/local-dev-stack/SKILL.md` with canonical contract keys and migration alias behavior.
2. [ ] Cross-link to the contract spec from relevant skill sections.

## P1.V Validation

1. [ ] Validate all new contract and skill references resolve to existing paths.
2. [ ] Verify no contradictory variable ordering between skill docs.
