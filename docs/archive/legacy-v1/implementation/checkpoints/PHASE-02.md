# Phase 02 Checkpoint — Catalog, Entitlement, and Redemption

Date: 2026-09-01
Status: completed
Human Interaction: 0

## Completed Tasks

P2-T001 through P2-T016 are complete. P3-T002 was completed early during the preceding
phase because its declared dependencies were already satisfied.

## Delivered Functionality

- Catalog features, products, immutable product versions, feature snapshots, prices, and
  publish/retire/current-version commands.
- Append-only entitlement grant history with grant, revoke, restore, audit, and deterministic
  server-side access resolution.
- Secure redemption batches, cryptographically generated codes, versioned HMAC digests,
  atomic one-time redemption, idempotency replay, per-user limits, rollback, and concurrency
  protection.
- Public catalog, entitlement, access, redemption, and feedback API boundaries with stable
  contracts and redacted errors.
- Typed `platform-client` catalog, entitlement, access, redemption, and feedback methods.
- Admin catalog and redemption query/command contracts that exclude code hashes and require
  explicit command confirmation/reasons.
- Deterministic Local AisenLens catalog, redemption, and entitlement fixtures, including
  active, paused, expired, closed, and revoked states.
- Headless P2 E2E and security coverage for catalog projection, access, entitlement reads,
  invalid redemption, CSRF, Origin/application forgery, concurrency, and secret redaction.

## Migrations

Phase 02 database changes are delivered by:

- `20260901050000_catalog_core.sql`
- `20260901051000_catalog_features_prices.sql`
- `20260901052000_catalog_commands.sql`
- `20260901053000_entitlement_grants.sql`
- `20260901054000_entitlement_commands.sql`
- `20260901055000_entitlement_access.sql`
- `20260901056000_redemption_schema.sql`
- `20260901057000_redemption_transaction.sql`
- `20260901058000_public_api_projections.sql`

All schema changes were applied through migrations and verified from clean Local resets.

## APIs and Client Surface

Public function routes include:

- `GET /v1/health`
- `GET /v1/apps/{slug}`
- `GET /v1/products/public`

Authenticated platform routes include:

- `GET /v1/session`
- `GET /v1/me`
- `GET /v1/me/entitlements`
- `GET /v1/access/{featureCode}`
- `POST /v1/redemptions`
- `POST /v1/feedback`

The client exposes typed methods for public products, entitlements, access checks,
redemption with an explicit `Idempotency-Key`, and feedback submission. Admin catalog and
redemption projections/commands are defined in `packages/contracts` for the next Admin API
implementation.

## Verification Evidence

The final clean `pnpm platform:verify` passed:

- Database tests: 499/499.
- RLS tests: 29/29.
- Edge Function shell tests: 4/4.
- Unit tests: 50/50.
- Contract tests: 8/8.
- Integration tests: 22/22.
- Playwright discovery: 7/7.
- Typecheck, lint, Prettier format check, workspace build, boundary check, and
  failure-propagation harness: PASS.
- Generated Supabase types remained stable across repeated generation.
- P2 Playwright suite: 3/3 passed headlessly.
- Redemption concurrency check: exactly one of two concurrent claims succeeded.
- Secret scan: passed for 165 tracked files.

One earlier full-gate attempt exposed test-order contamination when post-Auth catalog
fixtures ran before database tests. The verifier now executes clean database/RLS tests before
the post-Auth fixture promotion; the final clean gate passes with this order. The E2E browser
request helper was also narrowed to a serializable fetch-init shape so the workspace typecheck
and browser test use the same contract.

## Known Limitations and Deferred Items

- The Admin catalog/query/command HTTP implementation and UI are Phase 03/04 work; this
  checkpoint delivers their stable contracts only.
- Local fixtures intentionally use test-only values and do not establish commercial prices,
  production products, or production secrets.
- Vite reports the existing Admin bundle-size warning during a successful build. Node emits
  existing child-process deprecation warnings during some scripts; neither is a quality-gate
  failure.
- Supabase Local's outer Kong gateway may add its default CORS headers; the handler-level
  exact-Origin policy remains covered and must be preserved by the eventual deployment
  gateway configuration.

## Architecture and Human Review

Architecture Deviations: None
Human Interventions: 0
Production or staging resources were not touched.

## Git Range

Phase 02 implementation starts at `a5828b0` and runs through the Phase 02 checkpoint commit.
The material task commits are recorded in `docs/implementation/TASK_LEDGER.md`; the remote
branch is `origin/main`.

## Next Phase

Proceed to P3-T001 — finalize the Admin workspace under the repository AGENTS rules. P3-T002
is already complete; the subsequent Admin foundation tasks unlock the P4 Admin catalog,
customer, and product-integration path.
