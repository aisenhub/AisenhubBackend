# Phase P4 — Admin Catalog/Customer Operations and Product Integration

Goal: deliver Admin Phase B/C, account workflows, and AisenLens migration to platform-client without changing the approved architecture. Human Interaction Budget: **0**.

## P4-T001 — Implement complete Catalog and Redemption Resource Queries

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: api-contract  
Track: B/C  
Parallel Safe: yes

### Architecture References

- Main §11 Resource Query
- §15.4 Catalog/Growth IA
- §15.5 Product 360

### Dependencies

P2-T013,P3-T009.

### Goal

Add list/detail/overview queries for Applications, Origins, Features, Products, Versions, Prices, Batches, Codes hints, Redemptions, and Entitlements.

### Inputs

P2 domains, Admin query middleware/contracts.

### Files To Inspect

- P2 schema
- Admin query services
- contracts

### Files To Create

- Catalog/Redemption query handlers and overview tests

### Files To Modify

- Admin contracts/router

### Implementation Steps

1. Finalize explicit projections and filter allowlists.
2. Implement Product overview aggregation with feature diff/prices/batches/audit.
3. Return code hint only.
4. Apply Action checks and field redaction.
5. Add pagination/search/sort tests.

### Commands

```bash
pnpm test:contract
pnpm functions:test -- admin-catalog-query
pnpm test:integration -- admin-catalog-query
```

### Tests

Every resource/role/filter/page/detail/overview, invalid filter, sensitive code/hash exclusion.

### Acceptance Criteria

- [ ] All IA resources have typed queries.
- [ ] Product overview uses existing facts only.
- [ ] No plaintext/hash leaks.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not add a generic table endpoint or second read store.

### Output

Catalog/Redemption query API.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(admin-api): add catalog redemption queries` — Task P4-T001.

### Next

P4-T002 and P4-T006.

## P4-T002 — Implement safe Catalog draft mutations

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: api-domain  
Track: A/B/C  
Parallel Safe: yes

### Architecture References

- Main §11 Business Command and Draft exception
- §8.3 catalog invariants

### Dependencies

P2-T003,P4-T001.

### Goal

Support explicit create/edit of Applications, Origins, Features, Products, draft Versions, and Prices without generic status mutation.

### Inputs

Catalog schema/contracts/Admin auth.

### Files To Inspect

- catalog functions
- Admin contracts

### Files To Create

- draft mutation contracts/handlers/tests

### Files To Modify

- platform-admin router
- Admin Data Provider create/update mapping

### Implementation Steps

1. Define allowlisted writable fields per resource.
2. Implement create/draft update with optimistic version conflict handling.
3. Prevent machine-ID mutation after use.
4. Route state changes to named commands only.
5. Audit sensitive config changes.

### Commands

```bash
pnpm test:contract
pnpm functions:test -- catalog-drafts
pnpm db:test
```

### Tests

Allowed fields, extra/status field rejection, SKU/slug/code immutability, conflict, role permissions, audit.

### Acceptance Criteria

- [ ] No arbitrary PATCH exists.
- [ ] Draft editing cannot publish/set-current.
- [ ] Errors are stable.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not expose database columns or allow direct status edits.

### Output

Safe Catalog draft operations.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(catalog): add controlled admin draft mutations` — Task P4-T002.

### Next

P4-T003.

## P4-T003 — Expose Catalog publish, retire, set-current, and production-origin Commands

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: api-security  
Track: B/F  
Parallel Safe: no

### Architecture References

- Main §11 Admin Commands
- §11.2 dangerous protocol
- §15.6

### Dependencies

P2-T003,P3-T003,P4-T002.

### Goal

Wrap catalog domain functions in typed high-risk Admin Commands.

### Inputs

Domain functions, command client/contracts, role matrix.

### Files To Inspect

- catalog functions
- Admin middleware
- command client

### Files To Create

- command handlers/integration tests

### Files To Modify

- contracts/command methods/router

### Implementation Steps

1. Require active member, Action, reason, AAL2, Idempotency-Key.
2. Validate typed confirmation for SKU/App slug where required.
3. Execute command/audit/idempotency atomically.
4. Return requestId/audit/entity links.
5. Test timeout/retry/double-click.

### Commands

```bash
pnpm functions:test -- catalog-commands
pnpm test:integration -- catalog-commands
pnpm --filter @aisenhub/admin-client test
```

### Tests

Every success/forbidden/MFA/reason/state/idempotency/confirmation/rollback path.

### Acceptance Criteria

- [ ] Named endpoints match architecture.
- [ ] Repeated request does not duplicate effects.
- [ ] Every success is audited.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not call state functions from browser/database SDK.

### Output

Catalog high-risk API Commands.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(admin-api): expose catalog business commands` — Task P4-T003.

### Next

P4-T005 and P4-T006.

## P4-T004 — Implement Redemption batch create/generate/pause/close Commands

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: api-security  
Track: B/F  
Parallel Safe: yes

### Architecture References

- Main §11 Admin Commands
- §8.6 one-time plaintext
- §15.6

### Dependencies

P2-T008,P2-T010,P3-T003,P4-T001.

### Goal

Provide secure batch lifecycle and one-time code generation through Admin Command Client.

### Inputs

Redemption generator/domain, contracts, Admin auth.

### Files To Inspect

- redemption services
- command transport

### Files To Create

- batch command handlers/tests

### Files To Modify

- contracts/admin-client/router

### Implementation Steps

1. Implement batch draft creation.
2. Require reason/AAL2/idempotency for generate/pause/close.
3. Return plaintext only from successful generate response.
4. Prevent retries from generating a second set.
5. Audit and redact logs/errors.

### Commands

```bash
pnpm functions:test -- redemption-admin
pnpm test:integration -- redemption-admin
pnpm secrets:check
```

### Tests

Roles, MFA, reason, double submit, timeout retry, lifecycle conflict, one-time plaintext, audit/redaction.

### Acceptance Criteria

- [ ] Generation retry returns same safe result within policy.
- [ ] History queries show hint only.
- [ ] No plaintext in logs/storage.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not regenerate/reveal historical plaintext.

### Output

Redemption Admin Commands.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(admin-api): add redemption batch commands` — Task P4-T004.

### Next

P4-T005 and P4-T007.

## P4-T005 — Build DangerousActionDialog and command hooks

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: frontend-security  
Track: E  
Parallel Safe: yes

### Architecture References

- Main §15.6
- Admin AGENTS §§30–33,56

### Dependencies

P3-T005,P3-T007,P4-T003,P4-T004.

### Goal

Create the shared Ant Design risk dialog and module hooks without embedding business logic.

### Inputs

Command client and risk metadata.

### Files To Inspect

- design primitives
- Admin scoped AGENTS

### Files To Create

- DangerousActionDialog
- MfaRequirement
- RequestTrace
- generic command hook/tests

### Files To Modify

- Admin components exports

### Implementation Steps

1. Compose Ant Modal/Form/Alert.
2. Require target/immutable ID/state/impact/reason/confirmation.
3. Prevent double submit and preserve logical idempotency key.
4. Display safe errors/requestId/audit/entity links.
5. Keep API/domain logic in hooks/callers.

### Commands

```bash
pnpm --filter admin test -- dangerous-action
pnpm --filter admin build
```

### Tests

Missing reason/confirmation, MFA state, loading/double click, timeout retry, error/request links, accessibility.

### Acceptance Criteria

- [ ] No default reason exists.
- [ ] Component makes no direct API call.
- [ ] Double submit is blocked.
- [ ] Tests/build pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not reimplement Ant Modal/Form or encode refund/publish logic.

### Output

Reusable dangerous operation UX.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(admin): add dangerous action workflow` — Task P4-T005.

### Next

P4-T006 and P4-T007.

## P4-T006 — Build Catalog operations and Product 360 UI

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: frontend  
Track: E  
Parallel Safe: no

### Architecture References

- Main §15.4–15.6
- Admin AGENTS §§34–43

### Dependencies

P4-T001,P4-T002,P4-T003,P4-T005.

### Goal

Implement Catalog lists/forms/details and Product 360 with controlled commands.

### Inputs

Queries, draft APIs, commands, Ant/Refine components.

### Files To Inspect

- Admin catalog module
- Data Provider
- command hooks

### Files To Create

- Applications/Origins/Features/Products/Versions/Prices pages
- ProductVersionDiff/Product 360 tests

### Files To Modify

- module registry/routes

### Implementation Steps

1. Use Refine/Ant list/form primitives and URL state.
2. Separate draft forms from publish/retire/current actions.
3. Render Product 360 aggregation and audit.
4. Apply permission guards and status semantics.
5. Handle all loading/empty/error/conflict states.

### Commands

```bash
pnpm --filter admin test -- catalog
pnpm test:e2e --grep ADM-B-CATALOG
pnpm --filter admin build
```

### Tests

CRUD-safe drafts, commands, role visibility/direct 403, URL filters, immutable published UI, Product overview.

### Acceptance Criteria

- [ ] No status edit row exists.
- [ ] Support/Finance restrictions match matrix.
- [ ] All API calls go through clients.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not duplicate Ant primitives or infer backend state.

### Output

Catalog operations UI.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(admin): add catalog operations and product overview` — Task P4-T006.

### Next

P4-T007.

## P4-T007 — Build Redemption operations UI and one-time download handling

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: frontend-security  
Track: E/F  
Parallel Safe: no

### Architecture References

- Main §15 Growth & Access
- §8.6 plaintext rule
- Admin AGENTS §45

### Dependencies

P4-T001,P4-T004,P4-T005.

### Goal

Operate batches/codes/redemptions safely and handle generated plaintext exactly once.

### Inputs

Redemption queries/commands.

### Files To Inspect

- redemption module
- command hooks

### Files To Create

- batch/code/redemption pages
- RedemptionBatchSummary
- secure download helper/tests

### Files To Modify

- module registry

### Implementation Steps

1. Build server-driven lists/details.
2. Use dangerous dialog for generate/pause/close.
3. Create in-memory one-time file download then discard plaintext.
4. Show hints/status/history only afterward.
5. Block console/analytics/error persistence.

### Commands

```bash
pnpm --filter admin test -- redemption
pnpm test:e2e --grep ADM-B-REDEMPTION
pnpm secrets:check
```

### Tests

Generate/download, retry, navigation/history, permission roles, no plaintext storage/log, hint display.

### Acceptance Criteria

- [ ] Plaintext exists only in immediate response/download flow.
- [ ] Reload cannot reveal it.
- [ ] Support query-only and Finance deny work.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not store codes in localStorage/cache/analytics.

### Output

Secure Redemption operations UI.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(admin): add redemption operations` — Task P4-T007.

### Next

P4-T008.

## P4-T008 — Create account deletion request schema and recoverable workflow foundation

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: database-api-test-first  
Track: A/B/F  
Parallel Safe: yes

### Architecture References

- Main §8.2 account_deletion_requests
- §12.5 deletion workflow
- §17.5 retention

### Dependencies

P1-T008,P2-T005.

### Goal

Create deletion request state, user create/cancel API, and retry-safe worker foundation without deleting production data.

### Inputs

Profiles/sessions/grants/feedback.

### Files To Inspect

- identity/feedback schema
- retention rules

### Files To Create

- deletion migration
- user API contracts/handlers
- workflow tests

### Files To Modify

- platform-api router

### Implementation Steps

1. Create one-open-request constraint/status/attempt fields.
2. Implement reauthenticated user request and allowed cancel.
3. Revoke sessions/mark profile pending per transaction boundary.
4. Create idempotent local worker interface for later anonymization.
5. Test failure/retry states.

### Commands

```bash
pnpm db:reset
pnpm db:test
pnpm functions:test -- account-deletion
```

### Tests

Duplicate request, auth/re-auth, cancel states, session revocation, failed retry, no premature financial deletion.

### Acceptance Criteria

- [ ] State machine matches architecture.
- [ ] Cross-system step is retryable.
- [ ] No all-table hard delete exists.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not claim cross-Auth/DB ACID or invent retention years.

### Output

Deletion workflow foundation.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(identity): add recoverable account deletion workflow` — Task P4-T008.

### Next

P4-T009.

## P4-T009 — Implement User 360 and Customer Resource Queries

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: api-aggregation  
Track: B/C  
Parallel Safe: yes

### Architecture References

- Main §11 Overview APIs
- §15.5 User 360
- §13 role redaction

### Dependencies

P4-T001,P4-T008.

### Goal

Provide one authorized/desensitized User overview plus Feedback and Deletion request lists.

### Inputs

Profiles, grants, redemption, feedback, sessions summary, deletion requests, audit.

### Files To Inspect

- Admin query service
- Customer contracts

### Files To Create

- User overview/customer handlers/tests

### Files To Modify

- contracts/admin-client

### Implementation Steps

1. Define aggregation projection without second storage.
2. Include allowed profile/status/grants/redemptions/feedback/session summary/audit.
3. Apply Support/Finance field redaction.
4. Add filters and timeline links.
5. Validate contract.

### Commands

```bash
pnpm test:contract
pnpm functions:test -- customer-query
pnpm test:integration -- user-overview
```

### Tests

Each role projection, other user, deleted/pending profile, revoked/restore history, no token/IP leakage.

### Acceptance Criteria

- [ ] One overview request replaces browser fan-out.
- [ ] Fields are role-filtered server-side.
- [ ] Session token/security context never appears.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not expose payments before Commerce or join facts in browser.

### Output

Customer/User 360 API.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(admin-api): add customer and user overview queries` — Task P4-T009.

### Next

P4-T010 and P4-T011.

## P4-T010 — Expose Grant, Revoke, Restore, Disable User, and Deletion Commands

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: api-domain-security  
Track: B/F  
Parallel Safe: no

### Architecture References

- Main §11 Admin Commands
- §12.3–12.5
- §15.3 role matrix

### Dependencies

P2-T005,P3-T003,P4-T008,P4-T009.

### Goal

Expose customer operations through named, audited, idempotent Commands.

### Inputs

Entitlement/deletion domain functions and role matrix.

### Files To Inspect

- command contracts/client
- User overview

### Files To Create

- customer command handlers/tests

### Files To Modify

- contracts/admin-client/router

### Implementation Steps

1. Implement Grant/Revoke/Restore with exact role policy (Support no Restore).
2. Implement user disable with session revoke.
3. Implement Admin process-deletion command/worker transition.
4. Require reason/AAL2/idempotency and valid state.
5. Return requestId/audit links and invalidate overview.

### Commands

```bash
pnpm functions:test -- customer-commands
pnpm test:integration -- customer-commands
pnpm db:test
```

### Tests

Role/MFA/reason/state/idempotency, restore-new-grant, disable sessions, deletion retry, rollback/audit.

### Acceptance Criteria

- [ ] No status direct mutation endpoint.
- [ ] Restore creates new linked grant.
- [ ] Support cannot Restore.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not accept arbitrary features or erase audit/financial facts.

### Output

Customer Business Commands.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(admin-api): add customer operations commands` — Task P4-T010.

### Next

P4-T011.

## P4-T011 — Build User 360, Feedback, Entitlement, and Deletion UI

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: frontend  
Track: E/F  
Parallel Safe: no

### Architecture References

- Main §15.5 User 360
- §15.6 dangerous actions
- Admin AGENTS §§40–41,44

### Dependencies

P4-T005,P4-T009,P4-T010.

### Goal

Deliver role-filtered Customer operations with auditable dangerous actions.

### Inputs

Customer queries/commands and design components.

### Files To Inspect

- customers module
- User overview contract

### Files To Create

- User 360/Feedback/Deletion pages
- EntitlementPanel/UserSummary/AuditTimeline tests

### Files To Modify

- module registry/routes

### Implementation Steps

1. Render server-provided overview/timeline.
2. Implement Grant/Revoke/Restore/Disable/Process with dangerous dialog.
3. Hide fields/actions by role but test direct API denial.
4. Handle deletion statuses/retries.
5. Invalidate and refetch overview after commands.

### Commands

```bash
pnpm --filter admin test -- customers
pnpm test:e2e --grep ADM-C-CUSTOMER
```

### Tests

Owner/Admin/Support/Finance views/actions, restore semantics, disabled session, deletion progress, loading/errors.

### Acceptance Criteria

- [ ] Role field redaction matches backend.
- [ ] Every command shows requestId/audit.
- [ ] No browser entitlement calculation.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not let component fetch directly or edit status.

### Output

Customer operations UI.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(admin): add customer operations workspace` — Task P4-T011.

### Next

P4-T012.

## P4-T012 — Integrate account and AisenLens with platform-client

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: product-integration  
Track: C/D/F  
Parallel Safe: no

### Architecture References

- Main §6.2 AisenLens boundary
- §14 AisenLens config
- §19 Admin C/product switch

### Dependencies

P2-T012,P4-T008,P4-T010.

### Goal

Switch account and AisenLens to Platform API/feature codes and remove legacy Supabase/supporter assumptions.

### Inputs

platform-client, Local APIs, AisenLens repository path discovered at execution.

### Files To Inspect

- `apps/account`
- `E:/Projects/Aisenlens` current code and its AGENTS rules
- platform-client

### Files To Create

- account redemption/purchases/deletion UI
- AisenLens aisenhub service adapter/tests

### Files To Modify

- legacy AisenLens platform access only within authorized repository
- account routes

### Implementation Steps

1. Inspect AisenLens rules/dirty worktree before edits.
2. Add account catalog/redemption/entitlement/deletion pages through client.
3. Replace AisenLens supporter checks with feature-code access.
4. Remove/retire AisenLens platform migrations/RPC only after replacement tests.
5. Keep local video/project data untouched.

### Commands

```bash
pnpm --filter account test
pnpm --filter account build
pnpm test:e2e --grep PRODUCT-INTEGRATION
```

### Tests

Account flows, AisenLens free/paid/revoked session behavior, no platform table names, local-data nonregression.

### Acceptance Criteria

- [ ] AisenLens uses platform-client only.
- [ ] No platform migration remains in product repository when switch completes.
- [ ] Local media/project data is unchanged.
- [ ] Tests pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not broaden edits to AisenLens local media features or discard user changes.

### Output

Account and first-product integration.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`feat(integration): connect account and aisenlens platform access` — Task P4-T012.

### Next

P4-T013.

## P4-T013 — Run complete Admin B/C and product integration E2E

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: e2e-security  
Track: F  
Parallel Safe: no

### Architecture References

- Main §16.4 E2E
- Admin AGENTS §57

### Dependencies

P4-T006,P4-T007,P4-T011,P4-T012.

### Goal

Automate Catalog→Redemption→User Grant/Revoke/Restore→Audit and product access flows.

### Inputs

All P4 UI/API/products and role fixtures.

### Files To Inspect

- Playwright suites
- audit/query APIs

### Files To Create

- P4 cross-module E2E specs

### Files To Modify

- test orchestration

### Implementation Steps

1. Create Product/Version/Price, Publish, Set Current.
2. Create batch/generate/download/redeem.
3. Grant/Revoke/Restore User and verify product access.
4. Verify Audit Timeline/request IDs.
5. Repeat forbidden actions for Support/Finance and direct API.

### Commands

```bash
pnpm test:e2e --grep P4
pnpm secrets:check
pnpm boundaries:check
```

### Tests

Full stated flow, retries/double submit/forbidden roles, account/AisenLens outcome, plaintext redaction.

### Acceptance Criteria

- [ ] Headless E2E passes.
- [ ] Every state change has audit/requestId.
- [ ] No manual action or direct DB access.
- [ ] Security scans pass.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not include Refund before Commerce phase.

### Output

P4 cross-system proof.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`test(e2e): cover admin catalog customer integration` — Task P4-T013.

### Next

P4-T014.

## P4-T014 — Execute Admin B/C and product integration quality gate

Status: pending  
Phase: P4 — Admin Catalog / Customer + Product Integration  
Execution: AUTONOMOUS  
Type: quality-gate  
Track: F/G  
Parallel Safe: no

### Architecture References

- Main §19 Admin B/C acceptance
- §16 Test strategy

### Dependencies

P4-T001, P4-T002, P4-T003, P4-T004, P4-T005, P4-T006, P4-T007, P4-T008, P4-T009, P4-T010, P4-T011, P4-T012, P4-T013.

### Goal

Run full clean verification and create PHASE-04 checkpoint.

### Inputs

All P4 outputs.

### Files To Inspect

- P4 commits/tests
- progress/ledger

### Files To Create

- `checkpoints/PHASE-04.md`

### Files To Modify

- `PROGRESS.md`
- `TASK_LEDGER.md`

### Implementation Steps

1. Run platform verify and P4 E2E.
2. Run AisenLens/product tests in its repository context.
3. Repair/rerun.
4. Record cross-repository commits if applicable and exact evidence.

### Commands

```bash
pnpm platform:verify
pnpm test:e2e --grep P4
git status --short
```

### Tests

All phase quality categories and product integration suites.

### Acceptance Criteria

- [ ] All applicable checks PASS.
- [ ] Catalog/Redemption/Customer workflows are audited/idempotent.
- [ ] AisenLens boundary holds.
- [ ] Architecture Deviations is None or approved.
- [ ] Human interactions used: 0.

### Failure Recovery

Diagnose from full logs, repair the smallest architecture-compatible cause, rerun focused tests, then all task commands. Record any genuine architecture contradiction in an AB file.

### Do Not

Do not mark complete if external AisenLens changes are uncommitted/untracked in ledger.

### Output

PHASE-04 checkpoint.

### Human Gate

None. All Local operations and E2E are autonomous; commercial values remain deterministic test fixtures.

### Commit

`chore(checkpoint): complete admin catalog customer integration` — Task P4-T014.

### Next

P5-T001.
