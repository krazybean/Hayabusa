# Releasing Hayabusa

Hayabusa does not currently publish a packaged production release. This document defines the minimum gate for any future tagged release.

## Required checks

A release candidate must be based on `main` with:

- Hayabusa Validation workflow green
- Go unit tests and vet green for ingest and detection services
- Node API tests and syntax validation green
- Docker Compose configuration validation green
- end-to-end MVP smoke test green
- positive/negative detection scenario tests green
- documentation synchronized with the running stack
- no unresolved critical/high security issue known to the maintainer

## Release procedure

1. merge changes through a pull request
2. verify required CI on the merge commit
3. perform the real Windows collector runbook when collector code changed
4. review `docs/TECHNICAL_DEBT.md` for release-blocking items
5. create a versioned tag and release notes describing behavior changes, migrations, known limitations, and security-impacting changes

## Versioning

Until a stable public API exists, releases should remain pre-1.0 and may make breaking configuration/API changes when clearly documented.

## Rollback

A release must identify the previous known-good tag. Schema migrations must document whether rollback is safe before the release is published.
