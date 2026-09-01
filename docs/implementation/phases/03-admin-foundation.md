# Phase P3 — Admin Foundation (Admin Phase A)

Goal: deliver the secure Refine + Ant Design Admin shell, Providers, fixed RBAC, read-only operations, and automated UI/API proof. Human Interaction Budget: **0**.

Repository reality: read root `AGENTS.md` and the Admin rules currently stored in `app/AGENTS.md`; when scaffolding is complete, the latter must be preserved under its declared `apps/admin/AGENTS.md` scope.

## P3-T001 — Finalize Admin workspace under repository AGENTS rules

Status: completed
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: frontend-foundation  
Track: E/G  
Parallel Safe: no

### Architecture References

- Main §15.1 Admin stack
- Admin ADR §15 code structure
- root `AGENTS.md` §4
- current `app/AGENTS.md` §§4–10

### Dependencies

P1-T014,P2-T016.

### Goal

Finalize `apps/admin` as React/Vite/Refine/Ant Design and place the scoped AGENTS rules at their declared path.

### Inputs

P0 skeleton and existing `app/AGENTS.md`.

### Files To Inspect

- root `AGENTS.md`
- `app/AGENTS.md`
- `apps/admin` skeleton
- workspace graph

### Files To Create

- Admin Vite/Refine/Ant package config
- `apps/admin/AGENTS.md` preserving source content

### Files To Modify

- workspace scripts/boundary checks

### Implementation Steps

1. Verify rule priority and preserve the current Admin rules verbatim at scoped path.
2. Install compatible `@refinedev/core`, `@refinedev/antd`, Ant Design, React, Vite only.
3. Create module/app/provider directories.
4. Add forbidden UI framework/Tailwind-as-system/Supabase import checks.

### Commands

```bash
pnpm install
pnpm --filter admin typecheck
pnpm --filter admin build
pnpm boundaries:check
```

### Tests

Workspace build, dependency graph, scoped AGENTS presence/content hash, negative forbidden-import fixture.

### Acceptance Criteria

- [x] Admin builds with Refine + Ant Design.
- [x] Scoped AGENTS rules are preserved.
- [x] No second UI system/Supabase Data SDK exists.
- [x] Boundary tests pass.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not use shadcn/MUI/Tailwind component system or rewrite Ant primitives.

### Output

Rule-compliant Admin workspace delivered with separated app, provider, layout, and overview
module layers. Ant Design is the only UI system; Refine remains the application framework;
Admin source boundary checks reject alternate UI systems, Tailwind, and direct Supabase/
database imports. `apps/admin/AGENTS.md` remains byte-identical to the repository's original
Admin rules.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`chore(admin): finalize refine antd workspace` — Task P3-T001.

### Next

P3-T003 and P3-T004.

## P3-T002 — Implement Admin session and backend permission service

Status: completed
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: api-security-test-first  
Track: B/F  
Parallel Safe: yes

### Architecture References

- Main §11 Admin Session
- §8.7 Admin RBAC
- §15.3 role matrix

### Dependencies

P1-T003,P1-T005,P1-T008,P1-T010.

### Goal

Implement `GET /v1/admin/session` and reusable server-side permission checks.

### Inputs

Platform Session, admin_members, contracts/actions.

### Files To Inspect

- session middleware
- Admin session contract
- role matrix

### Files To Create

- Admin authorization middleware/service
- Admin session handler/tests

### Files To Modify

- platform-admin router

### Implementation Steps

1. Write non-admin/disabled/role/AAL/session expiry tests.
2. Resolve active membership on every request.
3. Return minimal identity/role/AAL/expiry.
4. Implement Action check helper and MFA requirement hook.
5. Ensure browser caches are never authorization inputs.

### Commands

```bash
pnpm functions:test -- admin-session
pnpm test:integration -- admin-auth
```

### Tests

All roles, normal user 403, disabled membership, expired/revoked session, AAL state, forbidden action.

### Acceptance Criteria

- [x] Admin session contract validates.
- [x] Normal user cannot enter Admin.
- [x] Permission helper reads current server state.
- [x] Tests pass.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not return database grants/full permission cache or create second login.

### Output

Admin identity and authorization kernel. Executed early during P1-T013 because all declared P3-T002 dependencies were already complete; no duplicate route or architecture deviation was introduced. Implementation is in `1c8d249`; database, integration, real Local HTTP, and full quality gates passed.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`feat(admin-api): add admin session and permission checks` — Task P3-T002.

### Next

P3-T003.

## P3-T003 — Define and test the complete fixed Admin Action matrix

Status: completed
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: contracts-security  
Track: C/F  
Parallel Safe: yes

### Architecture References

- Main §8.7 Action list
- §15.3 role matrix
- Admin AGENTS §29

### Dependencies

P3-T002.

### Goal

Encode one owner/admin/support/finance matrix shared by Backend tests and UI adapter.

### Inputs

Action registry and the exact main-architecture Actions: `applications.read`, `applications.change_production_origin`, `products.read`, `products.create`, `product_versions.publish`, `product_versions.retire`, `product_versions.set_current`, `redemption_batches.generate_codes`, `redemption_batches.pause`, `redemption_batches.close`, `entitlements.grant`, `entitlements.revoke`, `entitlements.restore`, `orders.read`, `order_items.refund`, `admin_members.manage`, `audit_logs.read`.

### Files To Inspect

- contracts Action registry
- Admin auth service

### Files To Create

- role-action matrix module
- matrix tests

### Files To Modify

- contracts exports
- backend permission mapping

### Implementation Steps

1. List every currently approved Action explicitly.
2. Map each role according to architecture.
3. Make unknown Actions deny by default.
4. Generate table-driven Backend and consumer fixtures.
5. Test Support/Finance high-risk boundaries.

### Commands

```bash
pnpm --filter @aisenhub/contracts test
pnpm functions:test -- admin-permissions
```

### Tests

Every role×Action cell, unknown action, disabled member, MFA-gated action policy.

### Acceptance Criteria

- [x] One matrix source drives fixtures without making client authoritative.
- [x] Unknown actions deny.
- [x] Support/Finance cannot exceed architecture.
- [x] Tests pass.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not add configurable roles/OpenFGA.

### Output

Fixed tested Admin Action matrix delivered from
`packages/contracts/src/admin-permissions.matrix.json`, with a typed contracts evaluator and a
Backend adapter. All 17 approved actions are covered for owner/admin/support/finance; unknown
actions, unknown roles, inactive members, and insufficient AAL2/MFA deny. Support entitlement
grant/revoke requires reason plus MFA; Support cannot restore; Finance cannot publish and can
refund only with MFA. Contract tests passed 11/11, the Admin permission smoke check covered 17
actions, the Edge Function runtime loaded the shared matrix, root tests passed 54/54, and
typecheck/lint/format/boundary checks passed.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`feat(authz): define admin action matrix` — Task P3-T003.

### Next

P3-T004 and P3-T005.

## P3-T004 — Implement admin-client Resource transport and Data Provider

Status: completed
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: client-contract  
Track: C  
Parallel Safe: yes

### Architecture References

- Main §15.2 providers
- Admin ADR §5
- Admin AGENTS §§16–18,54

### Dependencies

P2-T013,P3-T001.

### Goal

Implement typed Admin HTTP/resource mapping for list/get/search/filter/sort/pagination without business commands.

### Inputs

Admin contracts and base transport.

### Files To Inspect

- admin-client skeleton
- contract pagination
- Admin scoped rules

### Files To Create

- AisenHubAdminDataProvider
- mapping/error tests

### Files To Modify

- admin-client exports

### Implementation Steps

1. Map explicit Resource names to allowed URLs.
2. Implement server pagination/filter/sort/search serialization.
3. Validate response/total/page metadata.
4. Map 401/403/409/422/429/5xx and requestId.
5. Reject arbitrary resource/table names.

### Commands

```bash
pnpm --filter @aisenhub/admin-client test
pnpm boundaries:check
```

### Tests

Pagination/filter/sort/search, malformed response, stable errors, credentials/CSRF/requestId, arbitrary resource denial.

### Acceptance Criteria

- [x] Provider calls only `/v1/admin/*`.
- [x] No generic table mapping exists.
- [x] All contract tests pass.
- [x] No Supabase dependency.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not implement Publish/Refund/Grant through `update()`.

### Output

AisenHubAdminDataProvider delivered in `packages/admin-client/src/data-provider.ts` with explicit
products, productVersions, redemptionBatches, redemptionCodes, and redemptions resource routes.
It validates server-side query filters/sorts/pagination and response page metadata, maps item
reads to UUID-only paths, rejects unsupported resources before transport, and leaves business
commands outside the provider. Admin-client tests passed 5/5, typecheck, and boundaries passed.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`feat(admin-client): add resource data provider` — Task P3-T004.

### Next

P3-T006.

## P3-T005 — Implement typed Business Command Client foundation

Status: completed
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: client-security  
Track: C  
Parallel Safe: yes

### Architecture References

- Main §11.2 high-risk protocol
- §15.2 command client
- Admin AGENTS §§18,31–33,56

### Dependencies

P2-T013,P3-T001.

### Goal

Create command transport handling reason, confirmation, MFA errors, idempotency, retries, requestId, and cache invalidation signals.

### Inputs

Admin command contracts and base transport.

### Files To Inspect

- admin-client transport
- idempotency contracts

### Files To Create

- AisenHubBusinessCommandClient foundation
- command transport tests

### Files To Modify

- admin-client exports

### Implementation Steps

1. Define one typed method per available command, no URL strings in pages.
2. Generate/reuse Idempotency-Key per logical submission.
3. Allow safe retry after timeout without new key.
4. Map MFA/state/reason errors.
5. Return requestId/audit/entity links and invalidation metadata.

### Commands

```bash
pnpm --filter @aisenhub/admin-client test
```

### Tests

Missing reason, key reuse, double submit, timeout retry, state conflict, MFA, requestId, malformed response, invalidation.

### Acceptance Criteria

- [x] Pages need no idempotency implementation.
- [x] Retries cannot duplicate logical command.
- [x] Stable errors are typed.
- [x] Tests pass.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not place domain state machines in client.

### Output

Business Command transport foundation delivered in `packages/admin-client/src/command-client.ts`.
Six available catalog/redemption commands have typed methods, contract-validated inputs and
outputs, UUID-only targets, automatic logical idempotency keys, same-key safe retry for
transport failures, typed stable errors, requestId propagation, entity metadata, and explicit
cache invalidation signals. No state machine logic is present in the client. Admin-client tests
passed 8/8; root tests passed 60/60; typecheck, lint, format, workspace build, boundaries, and
secret scan passed.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`feat(admin-client): add command transport foundation` — Task P3-T005.

### Next

P3-T006.

## P3-T006 — Implement Refine Auth and Access Control Providers

Status: completed
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: frontend-security  
Track: E  
Parallel Safe: no

### Architecture References

- Main §15.2 providers
- Admin ADR §§6–7
- Admin AGENTS §§26–29

### Dependencies

P3-T002,P3-T003,P3-T004.

### Goal

Adapt Platform Session/Admin Action matrix to Refine while keeping Backend authoritative.

### Inputs

Admin session API, admin-client, role matrix.

### Files To Inspect

- Admin app providers
- contracts
- scoped AGENTS

### Files To Create

- auth-provider
- access-control-provider
- provider tests

### Files To Modify

- Refine app initialization

### Implementation Steps

1. Implement login redirect to account, check/getIdentity/logout/onError.
2. Keep identity/AAL only in memory/query cache.
3. Implement `can(resource,action)` from approved matrix.
4. Default-deny unknown routes/actions.
5. Test Backend 403 despite manipulated UI provider.

### Commands

```bash
pnpm --filter admin test -- providers
pnpm --filter admin typecheck
```

### Tests

Valid/expired/non-admin/disabled/MFA sessions, role cells, unknown action, manipulated client cache.

### Acceptance Criteria

- [x] No Admin password/JWT persistence.
- [x] UI permissions match matrix.
- [x] Direct forbidden API still returns 403.
- [x] Tests pass.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not treat provider result as server authorization.

### Output

Refine Auth and Access Control providers are delivered in `apps/admin/src/providers/`.
The Auth Provider redirects login to Account, checks the Backend Admin Session, keeps
session identity/AAL/CSRF state in memory, clears state on logout/auth errors, and never
persists an Admin password or JWT. The Access Control Provider evaluates the shared fixed
17-action matrix with default-deny behavior for unknown actions and MFA-required actions.
The Refine data-provider adapter keeps catalog reads explicit and rejects generic CRUD
mutations in favor of typed Business Commands. Provider tests passed 3/3; root tests passed
63/63; Admin typecheck/build, lint, format, and boundary checks passed. Existing Backend
Admin Session and forbidden-action tests retain server-authoritative 403 coverage.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`feat(admin): add auth and access providers` — Task P3-T006.

### Next

P3-T007.

## P3-T007 — Build Ant Design theme and reusable Admin domain primitives

Status: pending  
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: frontend-design-system  
Track: E  
Parallel Safe: yes

### Architecture References

- Main §6 design-system
- Admin AGENTS §§5–13,37–39,46–48

### Dependencies

P3-T001.

### Goal

Create theme/status/money/time/loading/error primitives by composing Ant Design, not replacing it.

### Inputs

Admin scoped component rules and AisenHub tokens.

### Files To Inspect

- packages/design-system
- Ant/Refine setup

### Files To Create

- ConfigProvider theme
- EntityStatus
- MoneyDisplay
- DateTimeDisplay
- Loading/Empty/Error/Permission states
- component tests

### Files To Modify

- design-system exports
- Admin root provider

### Implementation Steps

1. Define semantic tokens/status mapping.
2. Compose Ant Tag/Badge/Result/Spin/Typography.
3. Implement currency minor-unit and UTC/locale formatting.
4. Add accessibility and visual-semantic tests.
5. Keep domain-free primitives shared; Admin-specific components stay in app.

### Commands

```bash
pnpm --filter @aisenhub/design-system test
pnpm --filter admin test
pnpm --filter admin build
```

### Tests

Status mapping, money currencies/minor units, timezone exact/relative display, loading/error/accessibility.

### Acceptance Criteria

- [ ] Ant Design remains sole primitive system.
- [ ] No duplicated Button/Table/Form wrappers.
- [ ] Semantic components are tested.
- [ ] Build passes.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not add a second UI framework or business API calls.

### Output

Admin theme and presentation primitives.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`feat(design-system): add admin theme and status primitives` — Task P3-T007.

### Next

P3-T008.

## P3-T008 — Implement protected Admin shell, routing, errors, and notifications

Status: pending  
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: frontend  
Track: E  
Parallel Safe: no

### Architecture References

- Main §15.2–15.4
- Admin AGENTS §§20–22,46–48

### Dependencies

P3-T006,P3-T007.

### Goal

Build the secure Refine app shell with modular routes, Ant layout, protected navigation, global errors, and actionable notifications.

### Inputs

Providers, theme, role matrix.

### Files To Inspect

- Admin app shell
- module layout

### Files To Create

- protected route wrapper
- global layout/error boundary/notification provider
- module registry/tests

### Files To Modify

- router/Refine resources

### Implementation Steps

1. Register Overview/Catalog/Growth/Customers/Platform modules by permission.
2. Protect every route independently of menu visibility.
3. Map stable errors to safe UI.
4. Show requestId/audit/entity links in command notifications.
5. Represent not-yet-built Commerce as explicitly unavailable/hidden, not fake data.

### Commands

```bash
pnpm --filter admin test -- shell
pnpm --filter admin build
```

### Tests

Menu/route deny, deep link, 401 redirect, 403 page, error boundary, loading/empty, notification content.

### Acceptance Criteria

- [ ] Unknown/forbidden route is denied.
- [ ] No giant App.tsx/business logic.
- [ ] No scattered fetch URLs.
- [ ] Build/tests pass.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not expose unfinished Commerce as functioning data or use UI hiding as authorization.

### Output

Protected modular Admin shell.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`feat(admin): add protected refine shell` — Task P3-T008.

### Next

P3-T009.

## P3-T009 — Implement read-only Admin Query APIs and operational overview

Status: pending  
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: api-contract  
Track: B/C  
Parallel Safe: yes

### Architecture References

- Main §11 Resource Query
- §15.4 information architecture
- §15.7 Audit

### Dependencies

P3-T002,P2-T011.

### Goal

Provide read-only Applications, Users, Entitlements, Redemptions, Feedback, Audit, and System Health facts for Admin Phase A.

### Inputs

Existing domain tables and Admin auth middleware.

### Files To Inspect

- Admin query contracts
- P2 domains
- audit logs

### Files To Create

- query handlers/services
- system-health contract
- query tests

### Files To Modify

- platform-admin router
- contracts if approved list lacked exact projection

### Implementation Steps

1. Implement allowlisted filters/sort/cursor pagination.
2. Apply role-based field redaction.
3. Implement minimal actionable overview and system health from current services.
4. Return append-only Audit projections.
5. For Orders before Commerce, return no fake endpoint/data; keep UI capability explicitly unavailable until P5.

### Commands

```bash
pnpm test:contract
pnpm functions:test -- admin-query
pnpm test:integration -- admin-query
```

### Tests

Each role, filter/sort/page, redaction, invalid fields, Audit immutability, health safe output.

### Acceptance Criteria

- [ ] Queries match contracts.
- [ ] No SQL/arbitrary expression accepted.
- [ ] Support/Finance see only allowed fields.
- [ ] Tests pass.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not create second read store/CQRS or expose table names.

### Output

Phase-A Admin query surface.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`feat(admin-api): add read-only operations queries` — Task P3-T009.

### Next

P3-T010.

## P3-T010 — Build read-only Overview and resource pages with RBAC E2E

Status: pending  
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: frontend-e2e  
Track: E/F  
Parallel Safe: no

### Architecture References

- Main §15.3–15.5
- Admin AGENTS §§34,40–44,53–55

### Dependencies

P3-T008,P3-T009.

### Goal

Render actionable read-only pages and prove menu/route/button/API permissions for all roles.

### Inputs

Data Provider, query APIs, role fixtures.

### Files To Inspect

- Admin shell
- Design System
- Playwright roles

### Files To Create

- overview/app/users/audit/system-health pages
- DataTable/FilterBar/AuditTimeline
- RBAC Playwright specs

### Files To Modify

- module registry

### Implementation Steps

1. Use Refine useTable + Ant Table with URL state/server operations.
2. Build read-only Entity headers/timelines.
3. Handle loading/empty/error/denied.
4. Run owner/admin/support/finance menu/route/direct API matrix.
5. Verify Commerce unavailable state is truthful.

### Commands

```bash
pnpm --filter admin test
pnpm test:e2e --grep ADM-A
pnpm boundaries:check
```

### Tests

Provider components, URL persistence, role menu/route/page, direct forbidden API, field redaction, states.

### Acceptance Criteria

- [ ] All four role flows pass headlessly.
- [ ] Button hidden ≠ Backend permission is demonstrated.
- [ ] No browser-side bulk filtering or direct fetch.
- [ ] Tests/build pass.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not add write actions or beautiful-but-nonactionable BI.

### Output

Admin Phase A read-only operations UI.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`feat(admin): add read-only operations workspace` — Task P3-T010.

### Next

P3-T011.

## P3-T011 — Execute Admin Foundation quality gate

Status: pending  
Phase: P3 — Admin Foundation  
Execution: AUTONOMOUS  
Type: quality-gate  
Track: F/G  
Parallel Safe: no

### Architecture References

- Main §19 Admin Phase A acceptance
- §16.3 Admin Provider/RBAC
- Admin AGENTS §§53–59

### Dependencies

P3-T001, P3-T002, P3-T003, P3-T004, P3-T005, P3-T006, P3-T007, P3-T008, P3-T009, P3-T010.

### Goal

Prove Admin security shell and publish PHASE-03 checkpoint.

### Inputs

P3 code/tests/commits.

### Files To Inspect

- all P3 outputs
- progress/ledger

### Files To Create

- `checkpoints/PHASE-03.md`

### Files To Modify

- `PROGRESS.md`
- `TASK_LEDGER.md`

### Implementation Steps

1. Run clean platform verify.
2. Run Admin provider/component/RBAC/Playwright/build/boundary checks.
3. Repair and rerun full gate.
4. Record unavailable Commerce as known phase limitation, not deviation.

### Commands

```bash
pnpm platform:verify
pnpm test:e2e --grep ADM-A
pnpm --filter admin build
git status --short
```

### Tests

All applicable quality categories plus forbidden UI/Supabase imports.

### Acceptance Criteria

- [ ] All checks PASS.
- [ ] Admin only uses `/v1/admin/*`.
- [ ] Four-role UI/API matrix passes.
- [ ] Architecture Deviations is None or approved.
- [ ] Human interactions used: 0.

### Failure Recovery

Inspect the full failure, repair the smallest architecture-compatible cause, rerun focused tests and then all task commands. Document an Architecture Blocker only for a genuine design contradiction.

### Do Not

Do not advance with direct DB access or untested route permissions.

### Output

PHASE-03 checkpoint.

### Human Gate

None. Admin Local work and browser verification are autonomous; visual review is optional and nonblocking.

### Commit

`chore(checkpoint): complete admin foundation` — Task P3-T011.

### Next

P4-T001.
