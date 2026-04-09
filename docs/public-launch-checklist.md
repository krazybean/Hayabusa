# Public Launch Checklist

Use this before announcing the repository.

## 1. Repo Hygiene

Confirm internal local files are not tracked:

```bash
git ls-files AGENTS.md CLAUDE.md WORKING_CONTEXT.md security-platform-starter-bundle.zip
```

Expected:
- no output

## 2. Secret Check

Run:

```bash
rg -n --hidden -S '(SECRET|TOKEN|PASSWORD|PRIVATE KEY|BEGIN RSA|BEGIN OPENSSH|api[_-]?key|credential)' . --glob '!/.git/**'
```

Expected:
- no private keys
- no real tokens
- only intentional placeholders or environment variable references

## 3. Docs Check

Confirm the public entry points are aligned:

```bash
sed -n '1,220p' README.md
sed -n '1,220p' MVP_RUNBOOK.md
sed -n '1,220p' WINDOWS_REAL_HOST_RUNBOOK.md
sed -n '1,220p' docs/public-launch-checklist.md
```

Expected:
- Hayabusa is described as a self-hosted suspicious-login detection MVP
- the proven path is `ingest -> store -> detect -> alert`
- deferred scope is explicit
- the live Pages site is linked near the top of the README

## 4. Final Smoke Test

```bash
./scripts/dev-up.sh
./scripts/smoke-test.sh
docker compose logs --tail=120 alert-sink
./scripts/dev-down.sh
```

Expected:
- `Smoke test passed.`
- `alert-sink` shows `received method=POST path=/alerts/default`
- the stack is torn down again after verification

## 5. GitHub Pages

Verify:
- https://krazybean.github.io/Hayabusa/ loads
- the site copy matches the README

## 6. Final Readability Check

Before sharing the repo:

- confirm the README makes sense in under 2 minutes
- confirm root-level files look intentional
- confirm the live Pages link is easy to spot
- confirm MVP scope is clear and narrow
