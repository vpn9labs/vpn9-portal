# PR Title

## Summary
- What does this change do in 1–2 sentences?

## Motivation & Context
- Why is this needed? Link issues: `Fixes #123`, `Refs #456`.

## Changes
- Bullet the key code changes and affected areas.
- Mention new endpoints, jobs, env vars, or feature flags.

## Screenshots / UI (optional)
- Before / After images or short clip for UI changes.

## How To Test
- Setup: `cp .env.example .env` and adjust as needed.
- DB: `rails db:migrate` (if migrations added).
- Run app: `./bin/dev` and visit http://localhost:3000
- Run tests: `rails test` (or a specific file: `rails test test/services/build_info_test.rb`).

## Checklist
- [ ] Tests pass: `rails test` and any `rails test:system` as applicable
- [ ] Lint is clean: `bin/rubocop`
- [ ] Security scan (if relevant): `bin/brakeman`
- [ ] Docs updated (README/AGENTS/docs) when behavior or config changes
- [ ] No secrets committed; `.env.example` updated for new env vars
- [ ] DB migrations are reversible and scoped
- [ ] Frontend assets build: `bun run build` or `bun run build:css` when needed
- [ ] CI green (GitHub Actions)

## Deployment Notes
- Any required env vars, migrations, or runbooks.
- Reproducible build (release work): `make build`, optionally `make verify`, then `make publish`.
- Attestation/build info considerations if touching Docker or release paths.

## Breaking Changes
- Describe impact and mitigations, or state “None”.

## Additional Notes
- Anything reviewers should know (performance, tradeoffs, follow‑ups).

