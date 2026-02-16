# Security Policy

## Supported Versions

Security fixes are applied to the latest `main` branch.

## Reporting a Vulnerability

Please do not open public issues for security reports.

Use one of these channels:

1. GitHub Security Advisories (preferred): open a private report in this repository.
2. If advisories are unavailable, contact the maintainer privately and include `SECURITY` in the subject.

Include:

- A clear description of the issue and affected paths.
- Reproduction steps or a proof-of-concept.
- Impact assessment (confidentiality, integrity, availability).
- Suggested remediation (if available).

## Response Expectations

- Initial triage acknowledgement target: 3 business days.
- Remediation/mitigation target depends on severity and complexity.
- Coordinated disclosure is preferred after a fix is available.

## Scope

In scope:

- `superloop.sh` and modules under `src/`.
- Packages under `packages/` that are part of this repository.
- Scripts under `scripts/`.

Out of scope:

- Vulnerabilities only present in local developer environments.
- Third-party dependencies without a demonstrated impact path in this repository.
