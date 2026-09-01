# Local Development

The platform uses Docker-compatible Supabase Local for development and tests.
The local stack is isolated from Staging and Production; no cloud project or
production credential is required for the local quality gate.

Run the complete deterministic gate from the repository root:

```bash
pnpm platform:verify
```

The command checks or starts Supabase Local, resets only this local database,
verifies the Local Auth fixtures, regenerates database types twice, and runs
the database, RLS, function, unit, contract, integration, type, lint, format,
build, Playwright discovery, boundary, and failure-propagation checks.

The command intentionally leaves the local Supabase stack running for a faster
warm rerun. It does not contact Staging or Production and does not perform
broad Docker or filesystem cleanup.
