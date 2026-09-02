# AisenHub Platform Operations Runbook

This runbook describes the supported Local workflow and the safe handoff points
for Staging and Production. It follows the architecture boundary: PostgreSQL
and the Platform Backend remain the business authority, while Account, Admin,
SDKs, and browser tests consume API Contracts.

## Local rebuild and verification

Prerequisites are Docker Desktop with the Local daemon running, Node.js and
pnpm versions from `.tool-versions`, and the workspace dependencies. No cloud
project is required.

From the repository root:

```bash
pnpm install --frozen-lockfile
pnpm platform:verify
```

`platform:verify` starts Local Supabase when needed, resets only the Local
database, regenerates types twice, verifies Auth/domain fixtures, runs database,
RLS, Function, unit, Contract, integration, type, lint, format, build, security,
secret, E2E-discovery, boundary, and failure-propagation checks.

For the release-candidate journey, including a real browser Account flow and
Commerce resilience scenarios, run:

```bash
pnpm test:e2e:release
```

The release runner uses Local-only fixtures and isolated Account/Admin ports
`5176`/`5177` by default. Override them only for a known isolated environment:

```powershell
$env:PLAYWRIGHT_BASE_URL = 'http://localhost:5176'
$env:PLAYWRIGHT_ADMIN_BASE_URL = 'http://localhost:5177'
pnpm test:e2e:release
```

## Local environment and secrets

The committed `supabase/.env.example` contains names and Local-safe placeholders
only. Never replace a placeholder with a credential in Git. Supabase Local
status provides disposable local keys for the function runtime; the Playwright
configuration writes those keys plus non-secret test values to the ignored
`supabase/.temp/playwright-functions.env` file at test startup.

For a manual Function session, use an ignored local env file and set:

- `SUPABASE_URL` and the Local anon/service-role keys from `pnpm exec supabase
  status --output env`;
- `REDEMPTION_PEPPER` and `PAYMENT_WEBHOOK_SECRET_LOCAL` to Local-only test
  values;
- `PLATFORM_RUNTIME_ENVIRONMENT=local` and the cleanup/alert settings from the
  example file.

The service-role key, redemption pepper, webhook secret, Auth token, cookies,
and payment credentials must never appear in browser code, logs, screenshots,
fixtures committed to Git, or public environment variables.

## Recovery order

Use the smallest recovery action that restores the failing layer:

1. Check `pnpm exec supabase status` and Docker Desktop health.
2. Retry the focused command and preserve its request ID/error code.
3. Run `pnpm fixtures:verify` when Auth/domain fixtures are missing.
4. Run `pnpm db:reset` only when Local state is contaminated or a clean reset is
   required by the task, then run `pnpm fixtures:verify`.
5. Regenerate types with `pnpm supabase:typegen` and rerun the failed quality
   gate.
6. Finish with `pnpm platform:verify` before declaring the Local state healthy.

Do not reset Staging or Production as a Local recovery action. Do not delete
Docker/WSL data as part of an application test recovery.

## Change and release order

For every schema or backend change:

1. Create a new migration; never edit a published migration.
2. Reset Local and run database/RLS tests.
3. Generate and review Supabase types.
4. Run Function, Contract, integration, security, and boundary checks.
5. Build and run the applicable E2E journey.
6. Update implementation docs and the task ledger in the same task group.

Staging deployment, external secret configuration, and production cutover are
Human Gates. Before those gates, prepare the migration order, smoke commands,
rollback plan, and evidence; do not apply them to an external environment
without the required authorization.

## Evidence and code export

Use the task ledger, progress snapshot, phase report, and checkpoint as the
authoritative evidence chain. A safe export includes source, migrations,
contracts, tests, scripts, documentation, lockfile, and generated types. It
does not include `.env`, ignored Local env files, browser storage, Playwright
traces containing credentials, or database dumps with user/payment data.

Before sharing a commit range:

```bash
git status --short
git log --oneline --decorate -n 10
pnpm secrets:check
pnpm boundaries:check
```

Preserve unrelated user changes in the worktree. Never use a destructive reset
or checkout to make an export appear clean.

Architecture Deviations: None
