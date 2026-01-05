# Supergent Productization: Phase 1

Goal:
- Establish a minimal product-ready foundation for the Supergent wrapper.

Scope:
- Add licensing, versioning, and a first-pass config schema/validation.
- Add a minimal CI scaffold that runs local validation without network calls.

Requirements:
1) Add a LICENSE file (MIT) at repo root.
2) Add a CHANGELOG.md at repo root with an entry for the current release.
3) Add `--version` flag to `ralph-codex.sh` and print a version string.
4) Add a JSON schema file describing `.ralph/config.json` (minimal, but accurate to current fields).
5) Add a `validate` command that checks a given config file against the schema.
6) Add a CI workflow (GitHub Actions) that runs validation and a smoke test in dry-run mode.

Constraints:
- Do not require network access for validation or CI.
- Keep scripts bash 3.2 compatible.

Verification:
- `./ralph-codex.sh --version` prints a version string.
- `./ralph-codex.sh validate --repo .` succeeds on the repo's config.
- CI workflow config exists and runs the validation command and `self-check.sh --dry-run` or equivalent.

Completion:
- Output <promise>READY</promise> only when all requirements are satisfied.
