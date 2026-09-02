# API and Database Type Generation

`packages/contracts` is the only source of shared request, response, error,
permission, and API types. The generated Supabase database types are used only
inside the backend/data-access boundary; Account and Admin do not consume table
schemas directly.

## Local generation

After a migration or a function contract change:

```bash
pnpm supabase:typegen
pnpm typecheck
pnpm test:contract
pnpm boundaries:check
```

The generator reads the Local Supabase schema and writes
`supabase/types/database.ts`. Run it twice when checking determinism:

```bash
pnpm supabase:typegen
pnpm supabase:typegen
```

The second run must produce no further change. `pnpm platform:verify` performs
this stability check automatically.

## Contract change order

1. Update the appropriate file under `packages/contracts/src`.
2. Update all Platform API, Admin API, client, and test consumers.
3. Run Contract tests and generated-type stability checks.
4. Run typecheck, integration tests, boundary checks, and the relevant E2E
   journey.
5. Record the compatible API change in the phase report.

Do not make a frontend infer an entitlement, order state, permission, or error
from an untyped response. Do not expose database names, SQLSTATE, stack traces,
service-role material, or secret hashes through a Contract.

## Runtime environment

Local Function tests use disposable Local values. Staging and Production must
load credentials from their approved secret/environment manager. Credentials
must not be copied into `.env.example`, generated types, API fixtures, browser
bundles, or documentation.

Architecture Deviations: None
