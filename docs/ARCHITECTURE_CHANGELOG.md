# AisenHub Platform Architecture Changelog

## 2026-09-03 — Breaking Rebuild edition adopted

The Unified Identity Platform model remains the target, but the previous migration-oriented V2 rollout strategy is superseded.

### Why

The project currently has no real production users/data and no external API consumers requiring compatibility. Maintaining `/v1` legacy Cookie Auth beside `/v2` OAuth would add code, tests and operational work with no user benefit.

### Changed

- V2 becomes a direct breaking rebuild rather than a compatibility migration.
- The new clean API remains `/v1`; old internal `/v1` behavior is not treated as a released contract.
- `platform.platform_sessions` / shared Platform Cookie Auth is removed from the target model.
- Authenticated Application identity comes from verified OAuth `client_id` binding.
- Application Membership becomes mandatory for app-scoped authenticated access.
- Redirect URI protocol configuration remains in Supabase OAuth Provider in the first release; no duplicate `oauth_redirect_uris` business table is required initially.
- No legacy Membership/User/Session backfill is planned.
- After behavior is proven, database migrations are squashed into a clean baseline series.
- Documentation stops accumulating process logs/checkpoints/reports.

### Preserved

- Global Identity/Profile model.
- Application Registry and exact browser Origin allow-list (with reduced authority).
- Catalog, Entitlement, Redemption and Commerce domain semantics.
- PostgreSQL transaction authority, RLS and privileged command boundaries.
- Admin RBAC/MFA and backend-only Business Commands.
- Audit, idempotency and security testing principles.
- Modular monolith architecture.

### Superseded sources

The repository state immediately before this decision is indexed under `archive/superseded-v2-migration/`.

## 2026-09-03 — Migration-oriented V2 adopted (superseded)

The earlier V2 introduced Global Identity + Application Membership + OAuth/OIDC but planned a `/v1`/`/v2` compatibility window and gradual legacy-session retirement. That rollout strategy is now archived.

## 2026-08-31 — Legacy V1 architecture

The previous multi-product platform and Admin architecture are indexed under `archive/legacy-v1/` and are historical only.
