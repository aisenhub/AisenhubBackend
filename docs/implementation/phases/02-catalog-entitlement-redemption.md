# Phase P2 — Catalog, Entitlement, and Redemption

Goal: implement the approved catalog, immutable entitlement history, deterministic access decisions, secure redemption, and minimum Admin contracts entirely on Local. Human Interaction Budget: **0**.

## P2-T001 — Create features, products, and product versions schema

Status: completed
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: database-test-first  
Track: A  
Parallel Safe: no

### Architecture References

- Main §8.3 features/products/product_versions
- §8.9 invariants
- §16.1 DB tests

### Dependencies

P1-T014.

### Goal

Implement stable app features, products, immutable product versions, and current-version linkage.

### Inputs

AisenLens seed and app registry.

### Files To Inspect

- P1 migrations
- seed
- architecture §8.3

### Files To Create

- catalog migration
- catalog invariant tests

### Files To Modify

- seed

### Implementation Steps

1. Write failing constraints/immutability tests.
2. Create features/products/product_versions with exact enums/checks/FKs.
3. Implement controlled current-version validation.
4. Seed draft AisenLens catalog.

### Commands

```bash
pnpm db:reset
pnpm db:test
```

### Tests

Unique/immutable code/SKU/version, valid current ownership/status, active product requirement, invalid merge strategy/type.

### Acceptance Criteria

- [x] Schema matches architecture.
- [x] Published version mutation fails.
- [x] Cross-product current version fails.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not store price or user entitlement in product/version.

### Output

Core catalog schema delivered in `a5828b0`: features, products, product versions, exact enum/check constraints, private RLS boundary, controlled current-version validation, published-version immutability, and deterministic draft AisenLens seed. Database tests passed 225/225; RLS, root quality, and build checks passed.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(catalog): add feature product version schema` — Task P2-T001.

### Next

P2-T002.

## P2-T002 — Create product feature snapshot and price schema

Status: completed
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: database-test-first  
Track: A  
Parallel Safe: yes

### Architecture References

- Main §8.3 product_prices/product_version_features
- §8.9 price/value invariants

### Dependencies

P2-T001.

### Goal

Implement immutable version feature snapshots and independent channel/currency prices.

### Inputs

Catalog tables.

### Files To Inspect

- catalog migration/tests

### Files To Create

- feature/price migration
- type/price tests

### Files To Modify

- AisenLens seed

### Implementation Steps

1. Create product_version_features with composite key.
2. Validate JSON value against feature type/merge strategy via controlled function.
3. Create product_prices and validity/status constraints.
4. Seed Version 1 features and test price.

### Commands

```bash
pnpm db:reset
pnpm db:test
```

### Tests

JSON types, duplicate features, amount/currency/windows, active price only on published version, external ID uniqueness.

### Acceptance Criteria

- [x] Price is not stored on version.
- [x] Feature values are validated.
- [x] Invalid windows/amounts fail.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not add Offer/Promotion engine.

### Output

Version feature and price model delivered in `25b415a`: composite feature snapshots with JSON type validation and published immutability, independent channel/currency prices, price-window and external-ID constraints, active-price publication guard, private RLS boundary, and deterministic draft AisenLens feature/price seed. Database tests passed 255/255.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(catalog): add feature snapshots and prices` — Task P2-T002.

### Next

P2-T003.

## P2-T003 — Implement catalog publish, retire, and set-current domain functions

Status: completed
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: domain-test-first  
Track: A  
Parallel Safe: no

### Architecture References

- Main §8.3 version semantics
- §8.9 constraints
- §11 Business Commands

### Dependencies

P2-T001,P2-T002.

### Goal

Enforce catalog state changes atomically through named functions.

### Inputs

Catalog schema and Admin actor context conventions.

### Files To Inspect

- catalog tables/tests
- idempotency baseline

### Files To Create

- catalog command functions migration
- state-machine tests

### Files To Modify

- audit helper if required

### Implementation Steps

1. Write transition and rollback tests.
2. Implement publish validation/freeze.
3. Implement retire rule preventing retirement of current version.
4. Implement set-current ownership/published/price checks.
5. Add safe search_path/minimum execute grants.

### Commands

```bash
pnpm db:reset
pnpm db:test
```

### Tests

Allowed/forbidden transitions, missing feature/price, wrong product, repeat request, rollback and audit hooks.

### Acceptance Criteria

- [x] No direct status/current update path remains.
- [x] Published snapshots are frozen.
- [x] Command functions have safe search_path/grants.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not let Refine CRUD determine state transitions.

### Output

Catalog state machine functions delivered in `ba9613a`: backend-only publish, retire, and set-current RPCs with fixed search paths, controlled trigger context, publication completeness checks, active-price checks, atomic retirement price updates, and direct-write rejection. Database tests passed 292/292; RLS, function, integration, root quality, and build checks passed.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(catalog): add controlled version commands` — Task P2-T003.

### Next

P2-T004 and P2-T013.

## P2-T004 — Create entitlement grant schema and immutable history constraints

Status: completed
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: database-test-first  
Track: A  
Parallel Safe: yes

### Architecture References

- Main §8.5 entitlement_grants
- §9 resolution
- §12.3 restore semantics

### Dependencies

P2-T002.

### Goal

Create auditable grants with snapshot source identity, revoke-only state, and restore linkage.

### Inputs

Products/versions and test users.

### Files To Inspect

- catalog migrations
- architecture entitlement fields

### Files To Create

- entitlement migration
- grant constraint tests

### Files To Modify

- seed fixtures

### Implementation Steps

1. Create grant fields/indexes/source uniqueness.
2. Constrain resolution mode and source types.
3. Prevent DELETE and revoked-to-active mutation.
4. Validate restore linkage shape.
5. Seed test grants only through later domain helper.

### Commands

```bash
pnpm db:reset
pnpm db:test
```

### Tests

Source uniqueness, invalid source/status/mode, delete/revive denial, restore self/cycle/invalid original.

### Acceptance Criteria

- [x] Grant history cannot be deleted/revived.
- [x] OrderItem source is reserved for later Commerce FK validation.
- [x] Indexes exist.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not add `is_pro`, role-based entitlement, balance, or usage columns.

### Output

Immutable entitlement storage delivered in `25a15cb`: append-only grant history with fixed snapshot resolution, source uniqueness, product/version ownership, revoke-only transitions, restore linkage validation, private RLS, and required lookup indexes. Database tests passed 325/325.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(entitlement): add grant history model` — Task P2-T004.

### Next

P2-T005.

## P2-T005 — Implement the single grant/revoke/restore domain operations

Status: completed
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: domain-test-first  
Track: A/F  
Parallel Safe: no

### Architecture References

- Main §12.4 grant_entitlement
- §12.3 revoke/restore
- §8.7 Audit

### Dependencies

P2-T003,P2-T004.

### Goal

Create one reusable grant path plus auditable revoke and restore-new-grant operations.

### Inputs

Grant schema, catalog, idempotency, actor context.

### Files To Inspect

- entitlement/catalog schema
- audit model requirement

### Files To Create

- grant/revoke/restore functions
- transaction tests

### Files To Modify

- audit helpers/migration

### Implementation Steps

1. Create append-only audit_logs if not yet present.
2. Write failure/rollback/idempotency tests.
3. Implement grant_entitlement with source validation.
4. Implement revoke active→revoked only.
5. Implement restore as a new `source_type = admin_restore` grant whose `restores_grant_id` points to the original revoked grant.
6. Write audit in same transaction.

### Commands

```bash
pnpm db:reset
pnpm db:test
pnpm test:integration -- entitlement-domain
```

### Tests

Valid grant, duplicate source, revoked grant, restore new ID, repeated restore policy, missing reason, rollback, audit/request link.

### Acceptance Criteria

- [x] All grant sources reuse one function.
- [x] Original grant remains revoked on restore.
- [x] Every success has audit.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not accept arbitrary feature lists or directly edit status from API.

### Output

Entitlement command core delivered in `faebd5b`: common grant path for admin/redemption/order-item sources, revoke-only operation, new-grant admin restore, one-time restore policy, append-only audit logs in the same transaction, and backend-only execution grants. Database tests passed 367/367; RLS, root quality, and build checks passed.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(entitlement): add grant revoke restore transactions` — Task P2-T005.

### Next

P2-T006.

## P2-T006 — Implement deterministic checkAccess resolution

Status: completed
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: domain-test-first  
Track: A/B/F  
Parallel Safe: yes

### Architecture References

- Main §9 Entitlement resolution
- §9.1 front-end limits

### Dependencies

P2-T004,P2-T005.

### Goal

Resolve all active nonexpired snapshot grants and merge feature values deterministically.

### Inputs

Feature strategies, grants, app/origin identity.

### Files To Inspect

- catalog/entitlement functions
- resolution rules

### Files To Create

- check_access DB/service function
- resolution matrix tests

### Files To Modify

- indexes if evidence requires

### Implementation Steps

1. Write strategy/expiry/order tests.
2. Resolve fixed version features and `hub.all_apps_access`.
3. Merge any_true/sum/max/min/latest with stable tie-break.
4. Return decision ID/source/expiry.
5. Expose only through server API path.

### Commands

```bash
pnpm db:test
pnpm test:integration -- access
```

### Tests

No grant, expired/revoked, multiple grants, every strategy, retired historical version, inactive app, stable latest tie-break.

### Acceptance Criteria

- [x] Callers do not merge locally.
- [x] Retired version preserves historical snapshot.
- [x] Result is deterministic.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not use products.current_version_id for historical grants.

### Output

Unified access decision delivered in `supabase/migrations/20260901055000_entitlement_access.sql`: backend-only `check_access` resolves active nonexpired snapshot grants, supports app-scoped and `hub.all_apps_access` matches, merges every approved strategy, and returns the allowed value, source SKUs, earliest finite expiry, and decision ID. Database tests passed 398/398; integration, root quality, typecheck, lint, format, and workspace build checks passed.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(entitlement): implement deterministic access resolution` — Task P2-T006.

### Next

P2-T007 and P2-T013.

## P2-T007 — Create redemption batch, code, and redemption schema

Status: completed
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: database-test-first  
Track: A  
Parallel Safe: yes

### Architecture References

- Main §8.6 Redemption
- §8.9 constraints
- §13.5 secrets

### Dependencies

P2-T002,P2-T004.

### Goal

Create batches, hashed codes, claims, per-user trace, and one-code-one-redemption constraints.

### Inputs

Catalog versions, users, grants, idempotency.

### Files To Inspect

- current migrations
- redemption architecture

### Files To Create

- redemption migration
- constraint/security tests

### Files To Modify

- seed batch fixtures

### Implementation Steps

1. Create batch/code/redemption tables and statuses.
2. Enforce code hash and one redemption/grant/idempotency relation.
3. Add time/per-user indexes.
4. Restrict direct browser access.
5. Seed only hashes/hints, never real plaintext.

### Commands

```bash
pnpm db:reset
pnpm db:test
pnpm rls:test
```

### Tests

Duplicate hash/claim, invalid times/status/limits, direct read/write denial, referential consistency.

### Acceptance Criteria

- [x] No plaintext code column exists.
- [x] One code maps to at most one redemption.
- [x] Sensitive tables are inaccessible to browser roles.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not log or seed recoverable production-like codes.

### Output

Secure redemption storage delivered in `supabase/migrations/20260901056000_redemption_schema.sql`: private batch/code/receipt tables, digest-only code persistence, one-time uniqueness, code state lifecycle, immutable receipts, and cross-entity consistency validation. Database tests passed 439/439 and RLS tests passed 29/29.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(redemption): add batch code redemption schema` — Task P2-T007.

### Next

P2-T008.

## P2-T008 — Implement one-time redemption code generation

Status: completed
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: domain-security  
Track: A/B/F  
Parallel Safe: yes

### Architecture References

- Main §8.6 one-time plaintext
- §13.5 code security
- §15.6 dangerous operations

### Dependencies

P2-T007.

### Goal

Generate cryptographically strong codes, persist HMAC hashes/hints only, and return plaintext once.

### Inputs

Local redemption pepper/version and batch.

### Files To Inspect

- redemption schema
- secret conventions

### Files To Create

- generation service/function
- entropy/redaction tests

### Files To Modify

- Local env example
- log filters

### Implementation Steps

1. Generate ≥128-bit random easy-entry codes.
2. Compute versioned HMAC server-side.
3. Persist hash/hint and return plaintext only in immediate response.
4. Add duplicate-safe retry and redaction.
5. Use Local-only pepper fixture.

### Commands

```bash
pnpm functions:test -- code-generation
pnpm db:test
```

### Tests

Entropy/format, uniqueness, persisted columns, one-time response, log/error redaction, missing pepper.

### Acceptance Criteria

- [x] Database cannot reconstruct plaintext.
- [x] Generation is transaction/idempotency ready.
- [x] No plaintext appears in logs/artifacts.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not use sequential IDs, plain SHA without pepper, localStorage, or analytics.

### Output

Secure code generator delivered in `supabase/functions/_shared/redemption-code.ts`: 26-character easy-entry random payloads provide more than 128 bits of entropy, versioned HMAC-SHA256 binds each code to the server Pepper, and `toRedemptionCodeRecord` excludes plaintext from persistence. Root tests passed 40/40 and the code-generation security smoke check, typecheck, lint, format, and workspace build passed.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(redemption): add secure code generation` — Task P2-T008.

### Next

P2-T009.

## P2-T009 — Write complete redemption transaction tests before implementation

Status: completed
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: test-first  
Track: F/A  
Parallel Safe: no

### Architecture References

- Main §12.1 Redemption transaction
- §16 critical tests

### Dependencies

P2-T005,P2-T007,P2-T008.

### Goal

Specify the full concurrent/idempotent redemption contract as failing tests.

### Inputs

Schemas/functions stubs and fixtures.

### Files To Inspect

- redemption/grant/idempotency tables
- test harness

### Files To Create

- redemption SQL concurrency/integration suites

### Files To Modify

- fixture builders

### Implementation Steps

1. Cover valid/invalid/expired/paused/closed cases.
2. Add same-code concurrent claims.
3. Add same request/same user/different user retry cases.
4. Add per-user limit, grant/audit, and rollback assertions.
5. Confirm tests fail for missing implementation for the right reasons.

### Commands

```bash
pnpm db:test -- redemption
pnpm test:integration -- redemption
```

### Tests

The enumerated architecture matrix including concurrency and transaction rollback.

### Acceptance Criteria

- [x] Every required scenario has deterministic assertions.
- [x] Concurrency runner is noninteractive/repeatable.
- [x] Tests fail before implementation without harness errors.
- [x] No secret leaks.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not implement transaction logic inside the test task except minimal interfaces.

### Output

Executable redemption specification delivered in `supabase/tests/0017_redemption_transaction.sql` and `scripts/test-redemption-concurrency.mjs`, covering the complete transaction matrix and a repeatable two-session same-code race. The specification is now green after P2-T010; database tests passed 475/475.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`test(redemption): specify transaction and concurrency behavior` — Task P2-T009.

### Next

P2-T010.

## P2-T010 — Implement atomic and idempotent redemption transaction

Status: completed
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: domain  
Track: A/B  
Parallel Safe: no

### Architecture References

- Main §12.1 transaction sequence
- §8.8 idempotency
- §17 PostgreSQL Functions rule in AGENTS

### Dependencies

P2-T009.

### Goal

Make all redemption specification tests pass through one controlled transaction.

### Inputs

Failing tests, hash input, user/session/app context.

### Files To Inspect

- P2-T009 tests
- grant function
- idempotency helper

### Files To Create

- redeem_code function/service

### Files To Modify

- platform-api service layer

### Implementation Steps

1. Use SECURITY DEFINER with fixed search_path/minimal grant.
2. Lock idempotency, code, and batch rows.
3. Validate batch/time/user limit and generic unavailable errors.
4. Create grant, redemption, code status, and audit atomically.
5. Return saved result for same retry and reject different actor/hash.

### Commands

```bash
pnpm db:test -- redemption
pnpm test:integration -- redemption
```

### Tests

Run all P2-T009 cases plus function permission/search_path checks.

### Acceptance Criteria

- [x] Exactly one concurrent claim succeeds.
- [x] Retry semantics match architecture.
- [x] Failures leave no orphan grant/redemption/audit.
- [x] All tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not split grant/code/audit across independent commits or expose function to browser roles.

### Output

Atomic redemption domain flow delivered in `supabase/migrations/20260901057000_redemption_transaction.sql`: service-role-only `redeem_code` locks idempotency/code/batch rows, validates batch state and limits, calls the common grant path, inserts the receipt and audit, updates the code, and persists replay results in one transaction. Database tests passed 475/475 and the two-session concurrency check passed.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(redemption): implement atomic redemption transaction` — Task P2-T010.

### Next

P2-T011.

## P2-T011 — Define and implement public catalog, entitlement, redemption, feedback contracts/APIs

Status: completed  
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: contracts-api  
Track: B/C  
Parallel Safe: yes

### Architecture References

- Main §11 platform-public/platform-api
- §9 access response
- §8.7 feedback

### Dependencies

P2-T003,P2-T006,P2-T010.

### Goal

Expose the approved product-facing APIs and feedback storage with stable contracts.

### Inputs

Catalog/access/redemption domains and app identity middleware.

### Files To Inspect

- contracts package
- platform-api/public routers

### Files To Create

- catalog/access/redemption/feedback contracts
- feedback migration/API
- route tests

### Files To Modify

- error registry
- routers

### Implementation Steps

1. Define contracts and runtime validation first.
2. Implement public catalog projection.
3. Implement entitlements/access and POST redemptions.
4. Create app-attributed feedback table/API.
5. Return stable errors/requestId and enforce session/origin/CSRF.

### Commands

```bash
pnpm test:contract
pnpm functions:test
pnpm test:integration -- P2-api
```

### Tests

Public visibility, access results, redemption errors, feedback attribution/validation/auth, sensitive-field exclusion.

### Acceptance Criteria

- [x] All approved P2 routes are typed/validated.
- [x] Feedback records server-derived app_id.
- [x] No table/error internals leak.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not expose internal price strategy, code hashes, grants, or audit tables.

### Output

P2 product API surface delivered in `db1584c`: public catalog projection, session-bound access and entitlement reads, hashed redemption command, server-attributed feedback command, stable runtime contracts/errors, and sensitive-field exclusion. Database tests passed 499/499, RLS 29/29, integration 22/22, contract 7/7, root tests 47/47, and all applicable typecheck/lint/format/boundary/function/build gates passed.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(api): add catalog entitlement redemption feedback APIs` — Task P2-T011 (`db1584c`).

### Next

P2-T012.

## P2-T012 — Implement platform-client catalog, entitlement, redemption, and feedback methods

Status: completed  
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: client  
Track: C  
Parallel Safe: yes

### Architecture References

- Main §6 platform-client
- §11.2 client boundary

### Dependencies

P2-T011.

### Goal

Give account/tools typed API methods without Supabase/table knowledge.

### Inputs

P2 contracts and transport.

### Files To Inspect

- platform-client transport
- P2 contracts

### Files To Create

- client domain modules/tests

### Files To Modify

- package exports

### Implementation Steps

1. Implement public catalog/read access methods.
2. Implement session-bound redemption and feedback with CSRF/idempotency.
3. Validate all responses.
4. Map stable user-facing errors without parsing DB text.

### Commands

```bash
pnpm --filter @aisenhub/platform-client test
pnpm boundaries:check
```

### Tests

Mock/Local API success, malformed payload, stable errors, CSRF/idempotency, no forbidden imports.

### Acceptance Criteria

- [x] All methods use contracts.
- [x] No table/Supabase dependency.
- [x] Retry policy cannot duplicate redemption.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not calculate final entitlements in client.

### Output

P2 platform-client delivered in `660a95b`: typed methods for public products, entitlements, access decisions, redemption, and feedback; contract-backed input/response validation; credentialed CSRF transport; and explicit caller-supplied idempotency keys for safe redemption retries. Package tests passed 5/5, root tests 49/49, typecheck, lint, format, boundary, and workspace build passed.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(client): add catalog entitlement redemption methods` — Task P2-T012 (`660a95b`).

### Next

P2-T013.

## P2-T013 — Add minimal Admin Query/Command contracts required by Catalog and Redemption

Status: completed  
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: contracts  
Track: C  
Parallel Safe: yes

### Architecture References

- Main §11 platform-admin
- §15 Query/Command split
- Admin ADR §5 Data Layer

### Dependencies

P2-T003,P2-T010.

### Goal

Define—not yet build UI—the exact Admin contracts consumed by upcoming Admin phases.

### Inputs

Catalog/redemption data and command semantics.

### Files To Inspect

- contracts/errors/actions
- Admin API list

### Files To Create

- Admin session/catalog/redemption query-command schemas/tests

### Files To Modify

- permission Action registry

### Implementation Steps

1. Define list/detail/pagination/filter shapes.
2. Define publish/retire/current and batch generate/pause/close commands.
3. Require reason/MFA/idempotency metadata where applicable.
4. Exclude database columns and code hashes.

### Commands

```bash
pnpm --filter @aisenhub/contracts test
pnpm test:contract
```

### Tests

Request/response validation, stable pagination, error/action uniqueness, sensitive-field rejection.

### Acceptance Criteria

- [x] Query and Command schemas are distinct.
- [x] No generic status PATCH contract exists.
- [x] All Admin P2 actions are registered.
- [x] Tests pass.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not shape backend around Refine CRUD convenience.

### Output

Admin P2 contract source delivered in `ac132fb`: whitelisted catalog queries with stable pagination, dedicated product/version/redemption projections, named publish/retire/current/generate/pause/close commands, reason/confirmation requirements, server-side MFA expectation, and code-hash exclusion. Contract tests passed 8/8, with typecheck, lint, format, and boundary checks passing.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`feat(contracts): add catalog redemption admin contracts` — Task P2-T013 (`ac132fb`).

### Next

P2-T014.

## P2-T014 — Seed full deterministic AisenLens catalog and redemption fixtures

Status: completed  
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: fixtures  
Track: A/F  
Parallel Safe: no

### Architecture References

- Main §14 AisenLens configuration
- §18.2 seed

### Dependencies

P2-T011,P2-T013.

### Goal

Provide stable fixtures for free, entitled, expired, revoked, and redemption scenarios.

### Inputs

AisenLens app/features/product/version/price and local users.

### Files To Inspect

- seed
- all P2 schemas

### Files To Create

- fixture verification tests

### Files To Modify

- `supabase/seed.sql`
- fixture constants

### Implementation Steps

1. Seed exact AisenLens features and lifetime product.
2. Publish Version 1 and set current through approved path or deterministic migration-safe seed.
3. Seed active/paused/expired batches and hash-only codes.
4. Seed grants for access strategy cases.
5. Verify two resets are identical.

### Commands

```bash
pnpm db:reset
pnpm fixtures:verify
pnpm db:reset
pnpm fixtures:verify
```

### Tests

Stable IDs/counts/statuses and absence of plaintext codes.

### Acceptance Criteria

- [x] AisenLens seed matches architecture.
- [x] All test states are represented.
- [x] Two resets match.
- [x] No production/commercial values are implied.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not set official price/marketing promises; use obvious test values.

### Output

Complete Local P2 fixtures delivered in `406069c`: the base seed remains a deterministic draft catalog, while the post-Auth local fixture verifier promotes AisenLens Version 1 through the approved publish/current commands and adds active/paused/expired/closed redemption batches, digest-only codes, and active/expired/revoked entitlement states. Clean database tests passed 499/499; two reset→fixture verification cycles passed; fixture seeding is idempotent and contains no redemption plaintext.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`test(fixtures): seed catalog entitlement redemption scenarios` — Task P2-T014 (`406069c`).

### Next

P2-T015.

## P2-T015 — Run P2 end-to-end and security flows

Status: completed  
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: e2e-security  
Track: F  
Parallel Safe: no

### Architecture References

- Main §16.3–16.5
- §12.1 Redemption

### Dependencies

P2-T011,P2-T012,P2-T014.

### Goal

Prove account/tool API access and redemption behavior without manual testing.

### Inputs

Local account/API, fixtures, platform-client.

### Files To Inspect

- P1 Playwright
- P2 APIs/client

### Files To Create

- P2 Playwright/API security specs

### Files To Modify

- test orchestration

### Implementation Steps

1. Show unpurchased state.
2. Redeem valid code and observe access.
3. Exercise invalid/expired/paused and repeat cases.
4. Verify revoke effect through API.
5. Run concurrent redemption separately.
6. Scan traces/logs for plaintext.

### Commands

```bash
pnpm test:e2e --grep P2
pnpm test:integration -- redemption-concurrency
pnpm secrets:check
```

### Tests

Main and negative P2 flows.

### Acceptance Criteria

- [x] E2E and concurrency tests pass headlessly.
- [x] Access changes immediately after grant/revoke.
- [x] No plaintext/secret is captured.
- [x] No user action is required.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not rely on visual/manual confirmation.

### Output

Automated P2 system proof delivered in `00a5de8`: headless Playwright 3/3 covers public catalog, server-resolved entitlements/access, invalid redemption stable error redaction, and forged application rejection; the repeatable concurrency runner confirms exactly one same-code winner; fixture verification has no plaintext codes; and the secret scan passes for 164 tracked files.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`test(e2e): cover entitlement and redemption flows` — Task P2-T015 (`00a5de8`).

### Next

P2-T016.

## P2-T016 — Execute Catalog/Entitlement/Redemption quality gate

Status: pending  
Phase: P2 — Catalog / Entitlement / Redemption  
Execution: AUTONOMOUS  
Type: quality-gate  
Track: F/G  
Parallel Safe: no

### Architecture References

- Main §19 Platform Phase 2 acceptance
- §16 Quality

### Dependencies

P2-T001, P2-T002, P2-T003, P2-T004, P2-T005, P2-T006, P2-T007, P2-T008, P2-T009, P2-T010, P2-T011, P2-T012, P2-T013, P2-T014, P2-T015.

### Goal

Run clean full verification and publish PHASE-02 evidence.

### Inputs

All P2 commits/tests.

### Files To Inspect

- P2 outputs
- progress/ledger

### Files To Create

- `checkpoints/PHASE-02.md`

### Files To Modify

- `PROGRESS.md`
- `TASK_LEDGER.md`

### Implementation Steps

1. Run clean reset/full platform verify.
2. Run P2 concurrency and browser suites.
3. Repair and rerun complete gate.
4. Record migrations/APIs/tests/Git range/deviations/interventions.

### Commands

```bash
pnpm platform:verify
pnpm test:e2e --grep P2
git status --short
```

### Tests

All applicable quality categories.

### Acceptance Criteria

- [ ] All applicable checks PASS.
- [ ] One-time/concurrency/idempotency/security evidence is recorded.
- [ ] Architecture Deviations is None or approved.
- [ ] Human interactions used: 0.
- [ ] Progress points to P3-T001/P4 dependency path.

### Failure Recovery

Read the full failure, fix the smallest architecture-compatible cause, rerun the focused test, then the complete task commands. Escalate only with a documented Architecture Blocker.

### Do Not

Do not advance on partial redemption coverage.

### Output

PHASE-02 checkpoint.

### Human Gate

None. Local Catalog/Entitlement/Redemption work is fully autonomous.

### Commit

`chore(checkpoint): complete catalog entitlement redemption` — Task P2-T016.

### Next

P3-T001.
