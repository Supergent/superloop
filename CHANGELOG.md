# Changelog

## 0.3.0 - 2026-01-05
- Rename the main wrapper script to `superloop.sh` (breaking change).

## 0.2.0 - 2026-01-05
- Replace codex-specific config with a generic runner abstraction (breaking config change).
- Add placeholder expansion for runner arguments and prompt mode selection.
- Split the wrapper into src modules with a build script (single-file output preserved).
- Rename branding to Supergent.

## 0.1.5 - 2026-01-05
- Fix approval decision updates so empty notes do not blank approval.json.

## 0.1.4 - 2026-01-05
- Add per-role timeout support to prevent hanging Codex runs.
- Add reviewer packet generation to reduce reviewer context load.

## 0.1.3 - 2026-01-05
- Add optional approval gating with `approve` command and decision logs.
- Include approval/decision artifacts in run summaries and reports.

## 0.1.2 - 2026-01-05
- Add `status --summary` to show latest gate/evidence snapshot from run summaries.
- Add CI report generation and upload of `report.html` artifact.

## 0.1.1 - 2026-01-05
- Add observability artifacts (events, run summary, timeline).
- Add `report` command to generate HTML loop reports.
- Expand evidence manifests with artifact hashes/mtimes and gate file metadata.

## 0.1.0 - 2026-01-05
- Add `--version` flag and version output.
- Add config schema and `validate` command.
- Add CI workflow for validation and dry-run smoke check.
- Add MIT license.
