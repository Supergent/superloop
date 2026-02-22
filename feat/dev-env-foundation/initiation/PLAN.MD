# dev-env-foundation: Initiation Plan

## Goal

Adopt a reproducible local developer environment baseline in Superloop using `devenv` + `direnv` + `portless`, and provide a safe bootstrap path for target repos (starting with Supergent).

## Scope

- Add root `devenv`/`direnv` stack files and environment cache hygiene.
- Add local environment doctor script and portless-aware Superloop UI launcher.
- Add target bootstrap profiles and script support for worktree-based repos.
- Align Superloop documentation with stable named localhost URLs.
- Align shared skill-pack guidance across Claude Code and Codex runtimes.

## Non-Goals

- Converting CI workflows to run inside `devenv`.
- Forcing all contributors to use `portless` with no bypass.
- Applying production runtime configuration changes.

## Primary References

- `handbook/features/INITIATION.MD` - Feature initiation requirements.
- `README.md` - Developer quick start and dashboard usage.
- `packages/superloop-ui/README.md` - UI package local dev and API examples.
- `docs/dev-env-stack.md` - Local stack contract and escape hatches.

## Architecture

The local stack is layered:

1. `devenv` pins repeatable tools and default environment variables.
2. `direnv` auto-loads per-repo environment contracts from `.envrc`.
3. `portless` assigns stable `*.localhost` routes while preserving raw localhost fallback (`PORTLESS=0`).

Bootstrap profiles in `scripts/dev-env/profiles/*` extend the same baseline into target repos without coupling target repos to Superloop internals.

## Decisions

- Keep the stack default-on but optional with explicit escape hatches (`USE_DEVENV=0`, `PORTLESS=0`).
- Use named URL `http://superloop-ui.localhost:1355/liquid` as the primary local dashboard endpoint.
- Support git worktrees in bootstrap validation using `git rev-parse` rather than checking for `.git/` directories.
- Treat repo skills as shared sources synchronized to both Claude Code and Codex.

## Risks / Constraints

- Developers without `devenv`/`direnv`/`portless` installed need clear diagnostics and fallback behavior.
- Package docs and scripts must stay synchronized to avoid mixed localhost/portless expectations.

## Phases

1. Establish Superloop baseline stack files and documentation.
2. Add bootstrap profile and scripts for target repos (Supergent profile first).
3. Validate local behavior and capture rollout guidance.
