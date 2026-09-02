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

For the full release-candidate Account and Commerce journey, see
[OPERATIONS_RUNBOOK.md](./OPERATIONS_RUNBOOK.md) and run:

```bash
pnpm test:e2e:release
```

The API/type-generation workflow is documented in
[API_GENERATION.md](./API_GENERATION.md); suspected boundary or credential
incidents follow [SECURITY_RESPONSE.md](./SECURITY_RESPONSE.md).

## Retention cleanup configuration

The `retention-cleanup` Edge Function is a service-only scheduled entrypoint.
It uses Local-safe technical defaults and accepts no caller-provided cutoffs:

| Variable | Local default | Scope |
| --- | ---: | --- |
| `PLATFORM_RUNTIME_ENVIRONMENT` | `local` | `local`, `staging`, or `production` |
| `PLATFORM_CLEANUP_SESSION_GRACE_SECONDS` | `86400` | Post-expiry session cleanup grace |
| `PLATFORM_CLEANUP_SECURITY_CONTEXT_RETENTION_SECONDS` | `2592000` | IP-hash cleanup age |
| `PLATFORM_CLEANUP_IDEMPOTENCY_RESPONSE_RETENTION_SECONDS` | `0` | Age after `expires_at` before response scrubbing |
| `PLATFORM_CLEANUP_BATCH_SIZE` | `100` | Maximum rows per category per invocation, 1–1000 |
| `PLATFORM_CLEANUP_DRY_RUN` | `false` | Count candidates without changing data |

These are operational defaults, not legal retention periods. Staging and
Production must explicitly provide every cleanup variable through their secret
or environment manager. The job only removes expired sessions, clears aged
security hashes, and scrubs expired idempotency response bodies; orders,
payments, grants, redemption facts, and audit records remain retained.
