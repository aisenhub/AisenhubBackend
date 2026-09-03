# P6-T007 Security and Architecture-Boundary Audit

Date: 2026-09-02  
Environment: Local Supabase and Docker-compatible runtime  
Result: PASS — no critical or high findings

## Scope

The audit covered Admin source and production assets, workspace dependency
boundaries, committed secret patterns, privileged SQL migrations, RLS/DB
negative coverage, API integration coverage, and the Local verification
orchestrator. The audit did not change the production environment or any
production credentials.

## Evidence

| Check | Result |
| --- | --- |
| `pnpm test:security` | PASS — 42 Admin JavaScript assets scanned; largest asset 660005 bytes; no credential, Service Role, Supabase Data API, database, or forbidden Admin dependency finding; privileged SQL `search_path` and Admin grants checked |
| `pnpm secrets:check` | PASS — 291 tracked files scanned |
| `pnpm boundaries:check` | PASS — 7 workspace manifests; Admin and Admin Client dependency/source restrictions hold |
| `pnpm db:test` | PASS — 39 files / 1014 assertions, including direct database negative and privileged-function coverage |
| `pnpm rls:test` | PASS — 3 files / 29 assertions |
| `pnpm test:integration` | PASS — 11 files / 58 tests, including Admin/API denial and safe-error paths |
| `pnpm platform:verify` | PASS — reset, stable type generation, DB/RLS, fixtures, functions, unit, contract, integration, typecheck, lint, format, build, security audit, secret scan, E2E discovery (20 tests), boundaries, and failure harness |

## Findings

No critical or high findings remain.

- Admin production assets contain no private keys, credential prefixes,
  Service Role variables, database URLs, redemption pepper, Supabase Data API
  imports, or PostgreSQL client references.
- Admin and Admin Client source boundaries reject direct database/Supabase
  access and the forbidden UI framework set.
- Every migration file containing `SECURITY DEFINER` also declares a fixed
  `search_path`; Admin SQL functions explicitly revoke public execution and
  grant execution to `service_role`.
- RLS and database tests cover anon/authenticated ownership boundaries,
  privileged paths, append-only audit behavior, session/CSRF boundaries,
  commerce/redemption/deletion/retention invariants, and Admin role denial.
- API integration tests cover forged origin/session/role requests, stable
  error mapping, and sensitive-field redaction.

## Known non-blocking observations

- Vite reports an existing largest vendor asset of approximately 660 KB and a
  chunk-size advisory; Admin page modules are route-lazy-loaded and the
  measured asset remains below the 750 KB audit threshold.
- Ant Design emits existing deprecation notices for `List`, `Modal`, `Alert`,
  notification, and table pagination APIs during E2E/build activity. They do
  not create a security or correctness finding and are deferred to a focused
  dependency-upgrade task.

Architecture Deviations: None.
