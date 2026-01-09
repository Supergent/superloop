# Validation Helpers

This folder contains lightweight validation utilities for Superloop loops. The
preflight checks are dependency-free; the web smoke test uses Playwright when
available.

## Preflight (HTML + Script Sanity)

Validates:
- HTML entry exists and is non-empty
- Required selectors/text are present
- Referenced scripts exist and are non-empty

Example:

```bash
node scripts/validation/bundle-preflight.js --repo . --config \
'{"entry":"feat/validation/fixtures/web/index.html","web_root":"feat/validation/fixtures/web","required_selectors":["#root"],"required_text":["Validation Fixture"]}'
```

## Web Smoke Test (Playwright)

Launches Chromium, loads the entry via a local static server, runs selector/text
checks, and optionally captures a screenshot.

```bash
node scripts/validation/web-smoke-test.js --repo . --config \
'{"entry":"feat/validation/fixtures/web/index.html","web_root":"feat/validation/fixtures/web","checks":[{"selector":"#root","should":"exist"}]}'
```

If Playwright is not installed and `optional: true`, the smoke test reports
`skipped` without failing.

## Fixture Runner

Run the local fixture preflight:

```bash
scripts/validation/run-fixture.sh
```

Add `--negative` to assert the missing-entry path fails as expected.
