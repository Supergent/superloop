# Phase 1 - Boolean Default Hardening

## P1.1 Shared Bool Parsing
1. [x] Add `bool_or_default` helper in `src/00-header.sh`.

## P1.2 Runtime Callsite Hardening
1. [x] Replace `state.active` parsing in `src/60-commands.sh` with helper-based parsing.
2. [x] Replace lifecycle booleans in `src/60-commands.sh` (`enabled`, `require_on_completion`, `strict`, `block_on_failure`).
3. [x] Replace `usage_check.enabled` parsing in `src/60-commands.sh`.
4. [x] Replace RLMS booleans in `src/60-commands.sh` (`output.require_citations`, `rlms.roles[$role]`).

## P1.3 Static Validation Hardening
1. [x] Replace lifecycle boolean parsing in `src/56-validate-static.sh`.

## P1.4 Regressions
1. [x] Add superloop regression: explicit `active=false` state does not trigger reentrant block.
2. [x] Add superloop regression: explicit `lifecycle.enabled=false` is rejected in run path.
3. [x] Add static validation regression: explicit `lifecycle.enabled=false` fails validation.
4. [x] Add RLMS regression: `rlms.roles.reviewer=false` disables reviewer RLMS execution.

## P1.V Validation
1. [x] `bats tests/superloop.bats --filter 'validate --static fails when lifecycle.enabled is explicitly false|run blocks reentrant invocation for the same active loop id|run does not treat state.active=false as active|run rejects explicit lifecycle.enabled=false in loop config|run --dry-run resolves lifecycle main ref to HEAD on detached checkout'`
2. [x] `bats tests/rlms.bats --filter 'rlms requested mode does not run when keyword is absent|rlms role override false skips reviewer execution|rlms hybrid mode auto-triggers on large context'`
