# Repository Governance

Hayabusa uses pull requests and automated validation as the normal path to `main`.

## Recommended `main` ruleset

Configure a GitHub branch ruleset for the default branch with:

- require a pull request before merging
- require status checks to pass
- required checks:
  - `static-validation`
  - `validate-mvp`
- block force pushes
- block branch deletion
- require conversation resolution before merge
- do not require an approving review while the project has a single maintainer; enable required approvals when there is an independent reviewer

The workflow itself is defined in `.github/workflows/dev-mvp-validation.yml`.

## Merge policy

- use squash merges for focused hardening/feature PRs
- keep a PR scoped to one coherent engineering concern where practical
- do not merge around a failing required check
- update architecture/status/security documentation in the same PR when behavior or trust boundaries change

## Security administration

For a public repository, enable GitHub private vulnerability reporting when available. `SECURITY.md` remains the public discovery point for reporting expectations, but exploit details should not be posted to a public issue.

## Why this is not encoded in source

Repository rulesets and private vulnerability reporting are GitHub repository administration settings. They are intentionally documented here because the source tree can describe the required policy but cannot enforce account-level repository settings by itself.
