# Phase P1 — Identity, Application, and Session

Goal: implement the approved unified identity/application/session boundary entirely on Supabase Local. Human Interaction Budget: **0**.

## P1-T001 — Create profiles schema and lifecycle constraints

Status: completed
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: database  
Track: A  
Parallel Safe: yes

### Architecture References

- Main architecture §8.2 `profiles`
- §13 Data access/security
- §16.1 Database tests

### Dependencies

P0-T012.

### Goal

Create the profile table, Auth-user linkage, status checks, timestamps, and immutable identity rules.

### Inputs

Supabase Auth schema and deterministic user fixtures.

### Files To Inspect

- `0001_aisenhub_platform_baseline.sql`
- fixture IDs
- architecture §8.2

### Files To Create

- next domain migration for profiles
- profile SQL tests

### Files To Modify

- `supabase/seed.sql`

### Implementation Steps

1. Write table/check/FK/index definitions in `platform`.
2. Add controlled profile creation path for Auth users.
3. Add status-transition and direct-access tests.
4. Extend deterministic seed.

### Commands

```bash
pnpm db:reset
pnpm db:test
pnpm rls:test
```

### Tests

Own/missing profile creation, invalid status, FK deletion behavior, anon/authenticated direct-table denial.

### Acceptance Criteria

- [x] Reset exits 0.
- [x] Five fixture profiles exist with stable IDs.
- [x] Invalid status and unauthorized direct access fail.
- [x] Database tests pass.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not copy passwords/tokens or add product-role fields to profiles.

### Output

Tested profile schema.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`feat(identity): add profile schema` — Task P1-T001.

### Next

P1-T002 and P1-T005.

## P1-T002 — Create platform applications and exact origins schema

Status: completed
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: database  
Track: A  
Parallel Safe: yes

### Architecture References

- Main architecture §8.2 `platform_apps` and `app_origins`
- §10.2 CORS/Origin
- §8.9 invariants

### Dependencies

P1-T001.

### Goal

Implement app registration and exact environment-specific origins as the server-derived app identity source.

### Inputs

Seed app slugs/origins and Local URLs.

### Files To Inspect

- profile migration
- `supabase/config.toml`
- architecture app/origin fields

### Files To Create

- application/origin migration
- constraint tests

### Files To Modify

- seed data

### Implementation Steps

1. Create `platform_apps` and `app_origins`.
2. Enforce unique immutable slug/origin and valid status/environment.
3. Seed AisenLens plus Local account/admin origins.
4. Test wildcard and duplicate rejection.

### Commands

```bash
pnpm db:reset
pnpm db:test
```

### Tests

Exact origin uniqueness, invalid wildcard/environment/status, slug immutability after reference.

### Acceptance Criteria

- [x] Tables/constraints match architecture.
- [x] No production wildcard origin can be seeded.
- [x] AisenLens and Local origins are deterministic.
- [x] Tests pass.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not create browser app secrets or trust `X-AisenHub-App` as identity.

### Output

Application/origin schema and fixtures.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`feat(application): add app and origin registry` — Task P1-T002.

### Next

P1-T003.

## P1-T003 — Create platform sessions and fixed admin membership schema

Status: completed
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: database  
Track: A  
Parallel Safe: no

### Architecture References

- Main architecture §8.2 `platform_sessions`
- §8.7 `admin_members`
- §10 session lifecycle

### Dependencies

P1-T001.

### Goal

Create hashed Platform Session persistence and simple fixed Admin RBAC membership.

### Inputs

Session field definitions and role fixtures.

### Files To Inspect

- identity migration
- Auth fixtures
- architecture §§8.2, 8.7

### Files To Create

- session/admin membership migration
- database tests

### Files To Modify

- seed roles for owner/admin/support/finance

### Implementation Steps

1. Create session table with token/csrf hashes, expiry, last-seen, revocation, minimized context.
2. Create `admin_members` with fixed role/status/created_by/disabled fields.
3. Restrict table access to controlled server paths.
4. Seed four local Admin memberships.

### Commands

```bash
pnpm db:reset
pnpm db:test
pnpm fixtures:verify
```

### Tests

Token hash uniqueness, invalid roles/statuses, one membership per user, session expiry/revocation checks.

### Acceptance Criteria

- [x] No raw session/CSRF token column exists.
- [x] Only four approved roles pass constraints.
- [x] Normal user has no Admin membership.
- [x] Tests and seed verification pass.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not add admin_roles/admin_permissions/OpenFGA or put membership in profile/JWT.

### Output

Session and Admin membership storage.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`feat(identity): add platform sessions and admin membership` — Task P1-T003.

### Next

P1-T004.

## P1-T004 — Implement Identity/Application RLS and grants

Status: completed
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: security-test-first  
Track: A/F  
Parallel Safe: no

### Architecture References

- Main architecture §13.1–13.4
- §16.1 Database/RLS tests

### Dependencies

P1-T001,P1-T002,P1-T003.

### Goal

Enforce schema exposure and least privilege for all P1 tables.

### Inputs

P1 tables and test role helpers.

### Files To Inspect

- all P1 migrations
- RLS harness

### Files To Create

- P1 RLS/grant migration
- allow/deny test matrix

### Files To Modify

- test role helpers

### Implementation Steps

1. Revoke anon/authenticated defaults.
2. Enable RLS as defense in depth.
3. Expose only approved projections/controlled functions.
4. Write allow/deny tests before granting required paths.

### Commands

```bash
pnpm db:reset
pnpm rls:test
pnpm db:test
```

### Tests

Anon, normal user, other user, each Admin role, and server-function contexts across every table/view.

### Acceptance Criteria

- [x] `platform` schema is not Data API exposed.
- [x] Direct session/admin table access is denied.
- [x] Approved own-profile projection works only as specified.
- [x] Allow/deny matrix passes.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not grant broad table access to make API work.

### Output

Verified P1 least-privilege boundary.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`test(security): enforce identity and application RLS` — Task P1-T004.

### Next

P1-T005 and P1-T006.

## P1-T005 — Define identity, application, and session API contracts

Status: completed
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: contracts  
Track: C  
Parallel Safe: yes

### Architecture References

- Main architecture §11 platform-api/platform-admin
- §10 login/session
- §15.2 Auth Provider

### Dependencies

P1-T001,P1-T002,P1-T003.

### Goal

Add typed schemas for session exchange/read/delete, me/profile, app identity errors, and Admin session.

### Inputs

Contract primitives and approved API paths.

### Files To Inspect

- contracts primitives
- P1 data fields
- architecture §11

### Files To Create

- identity/application/session contract modules
- contract fixtures/tests

### Files To Modify

- error-code and permission registries

### Implementation Steps

1. Define request/response schemas without database column leakage.
2. Add session/admin-session minimal identity views.
3. Register stable auth/origin/CSRF/Admin errors.
4. Publish explicit package exports.

### Commands

```bash
pnpm --filter @aisenhub/contracts test
pnpm --filter @aisenhub/contracts typecheck
```

### Tests

Valid/invalid examples, forbidden extra sensitive fields, unique errors/actions, backward-compat snapshots.

### Acceptance Criteria

- [x] Contracts cover `/v1/session/exchange`, `/v1/session`, `/v1/me`, `/v1/admin/session`.
- [x] Admin session contains only identity/role/AAL/expiry.
- [x] No hash, database permission, or secret is exposed.
- [x] Tests pass.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not return full permission cache or Supabase service credentials.

### Output

P1 API contracts.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`feat(contracts): define identity and session APIs` — Task P1-T005.

### Next

P1-T006 and P1-T007.

## P1-T006 — Implement profile and application read APIs

Status: completed
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: api  
Track: B  
Parallel Safe: yes

### Architecture References

- Main architecture §11.1 platform-public/platform-api
- §13 browser access

### Dependencies

P1-T004,P1-T005.

### Goal

Implement approved public app and authenticated `me` reads through Platform API.

### Inputs

P1 contracts, origin registry, session-independent Auth context where applicable.

### Files To Inspect

- Edge Function shared shell
- contracts
- P1 migrations

### Files To Create

- public app handler
- `GET /v1/me` handler/services
- API tests

### Files To Modify

- function router/shared validation

### Implementation Steps

1. Route requests through shared envelope/error/requestId middleware.
2. Implement public app projection and authenticated profile projection.
3. Validate response contracts server-side.
4. Prevent table/error leakage.

### Commands

```bash
pnpm functions:test
pnpm test:contract
pnpm test:integration
```

### Tests

Public active app, retired/missing app, authenticated self, unauthenticated request, malformed response guard.

### Acceptance Criteria

- [x] Routes return stable requestId envelopes.
- [x] Only approved fields are returned.
- [x] Inactive/missing resources use stable errors.
- [x] Contract/integration tests pass.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not allow browser-selected table/resource names.

### Output

Public app and me APIs.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`feat(api): add application and profile reads` — Task P1-T006.

### Next

P1-T007.

## P1-T007 — Implement secure Platform Session exchange

Status: completed
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: api-test-first  
Track: B/F  
Parallel Safe: no

### Architecture References

- Main architecture §10.1 login flow
- §10.3 lifecycle
- §11 session API

### Dependencies

P1-T003,P1-T005.

### Goal

Exchange a verified Supabase JWT for a random, hashed Host-only Platform Session cookie.

### Inputs

Local Auth users, session contract, service-only DB path.

### Files To Inspect

- session schema
- shared auth middleware
- contracts

### Files To Create

- session exchange service/handler
- crypto and API tests

### Files To Modify

- platform-api router

### Implementation Steps

1. Write failing exchange/cookie/hash tests.
2. Verify Supabase user server-side.
3. Generate strong session and CSRF tokens; store hashes only.
4. Set exact `__Host-aisenhub_session` attributes and return CSRF only in approved response.
5. Write requestId/audit-safe logs.

### Commands

```bash
pnpm functions:test -- session-exchange
pnpm test:integration -- session-exchange
```

### Tests

Valid/invalid/expired JWT, disabled profile, random-token uniqueness, no plaintext persistence, exact Cookie flags.

### Acceptance Criteria

- [x] Exchange succeeds for valid local user.
- [x] Cookie is Secure/HttpOnly/SameSite=Lax/Path=/ with no Domain.
- [x] Database stores only hashes.
- [x] Failure creates no session.
- [x] Tests pass.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not share parent-domain cookies or put session token in URL/localStorage.

### Output

Secure session exchange.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`feat(session): implement platform session exchange` — Task P1-T007.

### Next

P1-T008.

## P1-T008 — Implement session read, logout, revocation, and lifecycle

Status: completed
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: api-test-first  
Track: B/F  
Parallel Safe: no

### Architecture References

- Main architecture §10.3 session lifecycle
- §11 platform-api

### Dependencies

P1-T007.

### Goal

Validate Host-only sessions, expose minimal session state, revoke current/all relevant sessions, and handle expiry/last-seen safely.

### Inputs

Session exchange and contracts.

### Files To Inspect

- session handler/service
- session table

### Files To Create

- session middleware
- read/delete endpoints
- lifecycle tests

### Files To Modify

- shared request context

### Implementation Steps

1. Write expiry/revocation/multi-session tests.
2. Resolve cookie to hash and lock/validate safely.
3. Implement throttled last-seen updates.
4. Delete current session and clear cookie; add reusable revoke-all domain function for password/user disable flows.

### Commands

```bash
pnpm functions:test -- session
pnpm test:integration -- session
```

### Tests

Current session, expired/revoked/unknown token, single logout, multi-session isolation, revoke-all, last-seen throttling.

### Acceptance Criteria

- [x] Invalid sessions return 401 without internal reason leakage.
- [x] Logout revokes only current session.
- [x] Revoke-all invalidates every user session.
- [x] Tests pass.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not trust client expiry or update last_seen on every request.

### Output

Complete Local session lifecycle.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`feat(session): add validation and revocation lifecycle` — Task P1-T008.

### Next

P1-T009.

## P1-T009 — Implement exact Origin, CORS, and app declaration validation

Status: completed  
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: security-test-first  
Track: B/F  
Parallel Safe: yes

### Architecture References

- Main architecture §10.2 CORS/CSRF
- §8.2 app_origins
- §16.2 API tests

### Dependencies

P1-T002,P1-T008.

### Goal

Derive app identity from exact Origin and reject forged/mismatched declarations.

### Inputs

Origin registry and shared middleware.

### Files To Inspect

- request context
- app/origin migration
- Local origins

### Files To Create

- origin/CORS middleware
- security tests

### Files To Modify

- all platform-api response handling

### Implementation Steps

1. Write allow/deny preflight and credential tests.
2. Resolve Origin to one active app/environment.
3. Compare optional/required `X-AisenHub-App` declaration to derived slug.
4. Emit exact allow-origin/credentials headers only for registered origins.

### Commands

```bash
pnpm functions:test -- cors-origin
pnpm test:integration -- cors-origin
```

### Tests

Registered/unregistered/null/wildcard origin, inactive app/origin, forged header, mismatch, credentialed preflight.

### Acceptance Criteria

- [x] No credentialed wildcard response occurs.
- [x] Header cannot switch app identity.
- [x] Allowed origin is echoed exactly.
- [x] All negative tests pass.

### Verification Note

The application handler returns the exact registered Origin and never returns a wildcard. Supabase Local's outer Kong CORS plugin currently overwrites function response headers during `functions serve`; this runtime behavior must be configured separately in any gateway used for browser traffic.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not use `X-AisenHub-App` as authority or production wildcards.

### Output

Origin-derived app identity middleware.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`feat(security): enforce exact app origins and CORS` — Task P1-T009.

### Next

P1-T010.

## P1-T010 — Implement CSRF issuance and write-request enforcement

Status: completed  
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: security-test-first  
Track: B/F  
Parallel Safe: no

### Architecture References

- Main architecture §10.2 CSRF
- §11.2 contract rules
- §16 security tests

### Dependencies

P1-T007,P1-T008,P1-T009.

### Goal

Issue an in-memory client CSRF token bound to Platform Session and require it on every credentialed mutation.

### Inputs

Session csrf hash and request middleware.

### Files To Inspect

- session exchange/read contracts
- CORS middleware

### Files To Create

- CSRF verification helper
- attack/replay tests

### Files To Modify

- session response and write middleware

### Implementation Steps

1. Write missing/incorrect/cross-session tests.
2. Return token only through approved session flow.
3. Hash/compare server-side using constant-time comparison.
4. Require exact Origin, app declaration, session, and CSRF together for writes.

### Commands

```bash
pnpm functions:test -- csrf
pnpm test:integration -- csrf
```

### Tests

Missing/wrong/cross-session/revoked-session token, safe GET behavior, valid mutation precondition.

### Acceptance Criteria

- [x] Write without valid CSRF is rejected.
- [x] Token is not persisted by clients or logged.
- [x] Cross-session token fails.
- [x] Tests pass.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not rely on SameSite alone or expose CSRF hash.

### Output

Session-bound CSRF protection.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`feat(security): enforce session-bound csrf` — Task P1-T010.

### Next

P1-T011.

## P1-T011 — Implement account login and session shell

Status: completed  
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: frontend  
Track: D  
Parallel Safe: yes

### Architecture References

- Main architecture §5 domain responsibilities
- §10 login flow
- §6 package-client boundary

### Dependencies

P1-T005,P1-T007,P1-T008,P1-T010.

### Goal

Implement account Local login/logout/session bootstrap through Supabase Auth exchange and platform-client, without product functionality.

### Inputs

Local Auth, platform-client transport, session contracts.

### Files To Inspect

- `apps/account` shell
- platform-client
- P1 APIs

### Files To Create

- login/session pages and hooks
- frontend tests

### Files To Modify

- platform-client session methods
- account router

### Implementation Steps

1. Add PKCE-compatible Supabase Auth only inside account boundary.
2. Exchange verified token via platform-client.
3. Keep Platform Session cookie Host-only and CSRF in memory.
4. Implement logout and expired-session UX.
5. Add accessible loading/error states.

### Commands

```bash
pnpm --filter @aisenhub/platform-client test
pnpm --filter account test
pnpm --filter account build
```

### Tests

Client methods, login state reducer/hooks, token non-persistence, logout/error rendering.

### Acceptance Criteria

- [x] Account never shares Supabase browser storage with tools/Admin.
- [x] Platform client validates responses.
- [x] Build/tests pass.
- [x] No product-role logic exists.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not copy Supabase session to other apps or store Platform cookie/token manually.

### Output

Account authentication shell.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`feat(account): add platform session login shell` — Task P1-T011.

### Next

P1-T012.

## P1-T012 — Add automated Local Auth and multi-session E2E

Status: in_progress
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: e2e  
Track: F  
Parallel Safe: no

### Architecture References

- Main architecture §16.3 E2E
- §10 unified session

### Dependencies

P1-T006, P1-T007, P1-T008, P1-T009, P1-T010, P1-T011.

### Goal

Prove login, exchange, profile read, multi-session behavior, logout, revoke, CORS, and CSRF in browsers without manual interaction.

### Inputs

Five local users, account app, Local API.

### Files To Inspect

- Playwright fixtures
- account routes
- API test helpers

### Files To Create

- P1 Playwright specs and role fixtures

### Files To Modify

- test startup orchestration

### Implementation Steps

1. Start Local API/account automatically.
2. Log in fixture users through UI/API-approved path.
3. Exercise current and second browser contexts.
4. Test logout/revoke/expired/cross-origin failures.
5. Capture safe traces only on failure.

### Commands

```bash
pnpm test:e2e --grep P1
```

### Tests

Full scenario plus negative CORS/CSRF/session paths.

### Acceptance Criteria

- [ ] Playwright exits 0 headlessly.
- [ ] No manual login/click/check is required.
- [ ] Session Cookie is only sent to API host.
- [ ] Failure artifacts contain no secrets.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not weaken browser security flags for tests.

### Output

Automated P1 browser proof.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`test(e2e): cover identity and platform sessions` — Task P1-T012.

### Next

P1-T013.

## P1-T013 — Complete P1 contract and security matrix

Status: pending  
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: security  
Track: F  
Parallel Safe: no

### Architecture References

- Main architecture §16.2 API contracts
- §16.5 security tests
- §13 security boundary

### Dependencies

P1-T012.

### Goal

Close all P1 negative cases and verify app/session/Admin identity boundaries.

### Inputs

P1 APIs and tests.

### Files To Inspect

- all P1 tests
- contracts/error registry

### Files To Create

- missing matrix cases and coverage report

### Files To Modify

- tests only unless defects require scoped fixes

### Implementation Steps

1. Map every P1 route to auth, authorization, input, CORS, CSRF, timeout/body-limit cases.
2. Add Admin-session normal/disabled/non-admin/AAL cases.
3. Verify logs and responses redact sensitive data.
4. Run mutation and coverage checks where configured.

### Commands

```bash
pnpm db:test
pnpm rls:test
pnpm functions:test
pnpm test:contract
pnpm test:integration
pnpm test:e2e --grep P1
```

### Tests

Complete route/security matrix.

### Acceptance Criteria

- [ ] Every P1 route has success and required negative cases.
- [ ] Normal user gets 403 from Admin session.
- [ ] No raw token/hash/internal DB error appears.
- [ ] All commands pass.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not treat UI behavior as API authorization evidence.

### Output

P1 security/contract closure.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`test(security): complete identity session matrix` — Task P1-T013.

### Next

P1-T014.

## P1-T014 — Execute Identity/Application/Session quality gate

Status: pending  
Phase: P1 — Identity / Application / Session  
Execution: AUTONOMOUS  
Type: quality-gate  
Track: F/G  
Parallel Safe: no

### Architecture References

- Main architecture §19 Platform Phase 1 acceptance
- §16 Test strategy

### Dependencies

P1-T001, P1-T002, P1-T003, P1-T004, P1-T005, P1-T006, P1-T007, P1-T008, P1-T009, P1-T010, P1-T011, P1-T012, P1-T013.

### Goal

Run the complete phase gate, checkpoint evidence, and prepare P2/P3 branches.

### Inputs

All P1 outputs and commits.

### Files To Inspect

- P1 files/tests
- progress/ledger

### Files To Create

- `checkpoints/PHASE-01.md`

### Files To Modify

- `PROGRESS.md`
- `TASK_LEDGER.md`

### Implementation Steps

1. Run clean reset and full `platform:verify`.
2. Run P1 Playwright and security suites.
3. Repair failures and rerun entire gate.
4. Record migrations/APIs/tests/Git range/deviations/human interventions.

### Commands

```bash
pnpm platform:verify
pnpm test:e2e --grep P1
git status --short
```

### Tests

All applicable phase quality categories.

### Acceptance Criteria

- [ ] All applicable checks PASS.
- [ ] Checkpoint truthfully records evidence.
- [ ] Architecture Deviations is None or approved.
- [ ] Human interactions used: 0.
- [ ] Progress marks P2-T001 next and P3 waits for its declared P1 dependencies.

### Failure Recovery

Read the complete failing output, repair the smallest architecture-compatible cause, rerun the narrow test, then rerun this task's full command set. Create an Architecture Blocker only if the approved design is impossible to implement safely.

### Do Not

Do not advance with red/skipped applicable checks.

### Output

PHASE-01 checkpoint.

### Human Gate

None. This Local task must remain autonomous.

### Commit

`chore(checkpoint): complete identity application session` — Task P1-T014.

### Next

P2-T001; P3 contract-preparation work only where dependencies permit.
