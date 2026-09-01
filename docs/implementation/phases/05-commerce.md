# Phase P5 — Commerce and Admin Phase D

Goal: implement OrderItem-based Commerce, payment event handling, fulfillment, refund/chargeback, Order 360, and Admin operations entirely on Local fixtures. Human Interaction Budget: **0**.

## P5-T001 — Create orders and order_items schema with immutable purchase snapshots

Status: completed
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: database-test-first  
Track: A  
Parallel Safe: yes

### Architecture References

- Main §8.4 orders/order_items
- §8.9 money constraints
- §12.2 fulfillment

### Dependencies

P4-T014.

### Goal

Implement order and item facts, status fields, amount/refund bounds, and per-item product/version/price snapshots.

### Inputs

Catalog/prices/users.

### Files To Inspect

- P2 catalog schema
- architecture Commerce fields

### Files To Create

- Commerce migration
- order constraint tests

### Files To Modify

- test fixtures

### Implementation Steps

1. Write amount/status/FK/snapshot tests.
2. Create orders/order_items with exact state enums.
3. Enforce quantity 1 for entitlement products and refund bounds.
4. Protect snapshots after paid state.
5. Add useful indexes.

### Commands

```bash
pnpm db:reset
pnpm db:test
```

### Tests

Invalid amounts/currency/status/quantity, snapshot mutation, order item sums, user anonymization linkage.

### Acceptance Criteria

- [x] OrderItem is the smallest fulfillment/refund unit.
- [x] Snapshots retain SKU/name/terms.
- [x] Constraints/tests pass.
- [x] No entitlement is inferred by frontend.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not use order.id as grant source.

### Output

Orders and items model.

### Verification

- Migration: `supabase/migrations/20260901160000_commerce_orders.sql`
- Database tests: `supabase/tests/0027_commerce_orders.sql` — 38/38 assertions
- Full database suite: 737/737 tests passed
- Root unit suite: 94/94 tests passed
- Typecheck, lint, format check, workspace build, boundary check, and secret scan: PASS
- OrderItem snapshots are validated against the catalog and become immutable once the order is paid; fulfillment/refund source remains `order_items.id`, never `orders.id`.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`feat(commerce): add orders and order items` — Task P5-T001.

### Next

P5-T002.

## P5-T002 — Create payments and payment_events schema

Status: completed
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: database-test-first  
Track: A  
Parallel Safe: yes

### Architecture References

- Main §8.4 payments/events
- §12.3 states
- §11 webhook

### Dependencies

P5-T001.

### Goal

Store payment identities/status and unique external events without full credentials.

### Inputs

Orders and Local fake/manual providers.

### Files To Inspect

- Commerce migration
- secret/log rules

### Files To Create

- payment migration
- event uniqueness tests

### Files To Modify

- fixtures

### Implementation Steps

1. Create payment/event tables and statuses.
2. Enforce provider+external_event_id uniqueness.
3. Store raw event only as minimized validated payload if architecture permits; otherwise safe summary.
4. Add amount/currency/order consistency.
5. Restrict browser access.

### Commands

```bash
pnpm db:reset
pnpm db:test
pnpm rls:test
```

### Tests

Duplicate event, invalid states/amount/currency, cross-order event, direct role access denial.

### Acceptance Criteria

- [x] No full payment credentials stored.
- [x] External event uniqueness works.
- [x] Sensitive access denied.
- [x] Tests pass.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not choose/activate a real payment provider.

### Output

Payment/event model.

### Verification

- Migration: `supabase/migrations/20260901170000_commerce_payments.sql`
- Database tests: `supabase/tests/0028_commerce_payments.sql` — 38/38 assertions
- Full database suite: 775/775 tests passed; RLS suite: 29/29 tests passed
- Auth fixtures, Edge Function shell tests, unit 94/94, contracts 14/14, integration 32/32, Playwright 14/14: PASS
- Typecheck, lint, format check, workspace build, boundary check, failure-propagation harness, and secret scan: PASS
- Payment identities and event summaries are backend-only; `(provider, external_event_id)` is unique, cross-order/provider/amount/currency mismatches are rejected, and nested credential keys are rejected.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`feat(commerce): add payments and payment events` — Task P5-T002.

### Next

P5-T003.

## P5-T003 — Specify Commerce state machines and rollback behavior

Status: completed
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: test-first  
Track: F/A  
Parallel Safe: no

### Architecture References

- Main §12.2–12.3 Commerce transactions
- §16.1 Database tests

### Dependencies

P5-T001,P5-T002.

### Goal

Create failing executable specifications for paid fulfillment, partial/full refund, chargeback, delayed payment, and rollback.

### Inputs

Commerce schemas and grant function.

### Files To Inspect

- Commerce statuses
- entitlement domain

### Files To Create

- Commerce SQL/integration state suites

### Files To Modify

- fixtures

### Implementation Steps

1. Cover every allowed and forbidden Order/Payment/Item/Grant transition.
2. Cover multi-item atomic fulfillment and duplicate event.
3. Cover partial compensation vs full item refund.
4. Cover chargeback and delayed event after cancel.
5. Assert no half fulfillment/audit.

### Commands

```bash
pnpm db:test -- commerce-state
pnpm test:integration -- commerce-state
```

### Tests

Full architecture state matrix and rollback.

### Acceptance Criteria

- [x] Tests fail for missing domain functions, not harness errors.
- [x] Every transition has explicit expected outcome.
- [x] OrderItem→Grant source assertions exist.
- [x] Concurrency/retry cases exist through duplicate-event retry assertions.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not implement provider or domain logic in this test task.

### Output

Executable Commerce specification in `supabase/tests/0029_commerce_state_spec.sql`, covering multi-item atomic fulfillment, duplicate-event retry, delayed payment after cancellation, partial compensation, full OrderItem refund, grant source linkage, and chargeback expectations. The focused suite intentionally remains red until the later domain tasks implement the named functions: 24/29 expected failures, with no harness errors.

### Verification

- Focused test command: `pnpm exec supabase test db supabase/tests/0029_commerce_state_spec.sql`
- Expected red result: 24/29 assertions fail because the domain functions do not yet exist; all failures are explicit missing-function or downstream state assertions.
- No provider or Commerce domain logic was implemented in this test-first task.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`test(commerce): specify order payment refund states` — Task P5-T003.

### Next

P5-T004 and P5-T005.

## P5-T004 — Define Commerce and Admin Commerce API contracts

Status: pending  
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: contracts  
Track: C  
Parallel Safe: yes

### Architecture References

- Main §11 Admin/API/Webhook
- §15 Commerce IA
- §15.5 Order 360

### Dependencies

P5-T001,P5-T002.

### Goal

Define typed Order/Payment/Event/Overview/manual verify/refund/chargeback contracts and errors.

### Inputs

Commerce fields/state rules.

### Files To Inspect

- contracts
- Admin Actions

### Files To Create

- Commerce contracts/tests

### Files To Modify

- error/action registry
- client exports later

### Implementation Steps

1. Define user-safe order projection and Admin filtered list/detail/overview.
2. Define manual verify and OrderItem refund inputs including policy/reason.
3. Define provider webhook internal validation boundary.
4. Register state/conflict/payment errors.
5. Exclude credentials/internal raw payload.

### Commands

```bash
pnpm --filter @aisenhub/contracts test
pnpm test:contract
```

### Tests

Valid/invalid state requests, amount policy, pagination, sensitive fields, Action uniqueness.

### Acceptance Criteria

- [ ] Refund targets OrderItem.
- [ ] Overview links item to Grant.
- [ ] Contracts expose no secret/raw internal event.
- [ ] Tests pass.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not decide official refund policy; model explicit compensation/product-return choice from architecture.

### Output

Commerce contract source.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`feat(contracts): add commerce and refund APIs` — Task P5-T004.

### Next

P5-T005,P5-T006.

## P5-T005 — Implement atomic paid-order fulfillment

Status: pending  
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: domain  
Track: A/B  
Parallel Safe: no

### Architecture References

- Main §12.2 fulfill_paid_order
- §8.5 source_type order_item

### Dependencies

P5-T003,P5-T004.

### Goal

Make paid fulfillment tests pass with one transaction and one grant per OrderItem.

### Inputs

Payment event, order/items, grant_entitlement, audit/idempotency.

### Files To Inspect

- P5-T003 tests
- grant function

### Files To Create

- fulfill_paid_order function/service

### Files To Modify

- Commerce migration/services

### Implementation Steps

1. Insert/read unique event and lock payment/order/items.
2. Validate provider amount/currency and state.
3. Transition payment/order.
4. Grant each unfulfilled item with source_id=item.id.
5. Commit only when all items/audit succeed.

### Commands

```bash
pnpm db:test -- commerce-state
pnpm test:integration -- fulfillment
```

### Tests

Multi-item success, duplicate event, one item failure rollback, source uniqueness, amount mismatch.

### Acceptance Criteria

- [ ] Each item gets one independent Grant.
- [ ] Duplicate fulfillment adds nothing.
- [ ] Partial failure commits nothing.
- [ ] Tests pass.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not enqueue first-version fulfillment or source grants from order.id.

### Output

Atomic Commerce fulfillment.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`feat(commerce): implement paid order fulfillment` — Task P5-T005.

### Next

P5-T006.

## P5-T006 — Implement manual order verification Command

Status: pending  
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: api-security  
Track: B/F  
Parallel Safe: yes

### Architecture References

- Main §11 `orders/{id}/verify`
- §15.3 Finance permissions
- §11.2 dangerous protocol

### Dependencies

P5-T004,P5-T005.

### Goal

Allow authorized manual payment verification to drive the same fulfillment path.

### Inputs

Fulfillment service, Admin auth, contracts.

### Files To Inspect

- Admin command middleware
- Commerce contracts

### Files To Create

- verify handler/tests

### Files To Modify

- router/admin-client

### Implementation Steps

1. Require finance/owner or approved role, reason, AAL2, idempotency.
2. Validate manual channel evidence fields.
3. Call same fulfillment operation.
4. Audit request/result.
5. Return overview/request/audit links.

### Commands

```bash
pnpm functions:test -- manual-verify
pnpm test:integration -- manual-verify
```

### Tests

Roles, reason/MFA, duplicate/retry, amount mismatch, invalid state, audit/rollback.

### Acceptance Criteria

- [ ] Manual path cannot bypass fulfillment checks.
- [ ] Retry is idempotent.
- [ ] Unauthorized Admin gets 403.
- [ ] Tests pass.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not mark order paid by generic status update.

### Output

Manual verify Command.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`feat(admin-api): add manual order verification` — Task P5-T006.

### Next

P5-T007.

## P5-T007 — Implement OrderItem refund transaction

Status: pending  
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: domain-api-test-first  
Track: A/B/F  
Parallel Safe: no

### Architecture References

- Main §12.3 refund semantics
- §11 refund Command
- §8.4 refunded_amount

### Dependencies

P5-T003,P5-T005.

### Goal

Implement partial compensation and full item refund with exact Grant effects.

### Inputs

Order/item/payment/grant/audit/idempotency.

### Files To Inspect

- refund tests
- Commerce state

### Files To Create

- refund domain function/handler/tests

### Files To Modify

- contracts/admin-client/router

### Implementation Steps

1. Lock item/order/payment/grant and idempotency.
2. Validate amount and explicit retain/revoke policy.
3. Accumulate refunded amount and transition states.
4. Revoke item Grant only for full product return.
5. Audit in same transaction and return requestId.

### Commands

```bash
pnpm db:test -- refund
pnpm test:integration -- refund
pnpm functions:test -- refund
```

### Tests

Partial retain, full revoke, overrefund, duplicate/retry, different key, already refunded, multi-item order, rollback.

### Acceptance Criteria

- [ ] Refund always targets item.
- [ ] Full returned item revokes only its Grant.
- [ ] Whole order refunded only when all items qualify.
- [ ] Tests pass.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not revive original grants or use order-level source.

### Output

Audited idempotent OrderItem refund.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`feat(commerce): implement order item refunds` — Task P5-T007.

### Next

P5-T008.

## P5-T008 — Implement chargeback and delayed-event exception handling

Status: pending  
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: domain-api  
Track: A/B/F  
Parallel Safe: yes

### Architecture References

- Main §12.3 chargeback/delayed payment
- §15 Commerce exceptions

### Dependencies

P5-T005,P5-T007.

### Goal

Handle disputes/chargebacks and late paid events through controlled states and an Admin exception queue.

### Inputs

Payment events, grants, audit.

### Files To Inspect

- Commerce functions
- state tests

### Files To Create

- chargeback/exception services and tests

### Files To Modify

- Admin query contracts/router

### Implementation Steps

1. Implement disputed/chargeback transitions.
2. Revoke all affected item grants on chargeback.
3. Route paid-after-cancel to exception without fulfillment.
4. Expose safe exception Query and Command only if architecture-defined action permits.
5. Audit all outcomes.

### Commands

```bash
pnpm db:test -- chargeback
pnpm test:integration -- commerce-exceptions
```

### Tests

Duplicate/ordered/out-of-order events, chargeback grants, late event, unauthorized resolution, audit.

### Acceptance Criteria

- [ ] Late cancelled order is not auto-fulfilled.
- [ ] Chargeback revokes correct item grants.
- [ ] Exception is queryable/audited.
- [ ] Tests pass.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not auto-invent a new order or restore on dispute reversal.

### Output

Commerce exception handling.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`feat(commerce): add chargeback and exception handling` — Task P5-T008.

### Next

P5-T009.

## P5-T009 — Implement signed webhook adapter with Local fake provider

Status: pending  
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: api-security-test-first  
Track: B/F  
Parallel Safe: no

### Architecture References

- Main §11 payment-webhook
- §12.2 events
- §16.5 webhook security

### Dependencies

P5-T002,P5-T005,P5-T008.

### Goal

Implement provider-neutral signed webhook boundary and prove it with a Local fake provider.

### Inputs

Provider adapter interface, Local secret, fulfillment/exception services.

### Files To Inspect

- payment-webhook shell
- secret/log filters

### Files To Create

- adapter interface
- fake provider
- webhook handler/tests

### Files To Modify

- router/env example

### Implementation Steps

1. Verify signature against raw body and timestamp window.
2. Normalize external event to internal contract.
3. Persist unique event and dispatch domain flow.
4. Return safe retry semantics.
5. Redact signature/raw secret logs.

### Commands

```bash
pnpm functions:test -- webhook
pnpm test:integration -- webhook
pnpm secrets:check
```

### Tests

Valid/forged/replay/expired signature, duplicate event, out-of-order events, malformed payload, secret redaction.

### Acceptance Criteria

- [ ] Webhook uses no user JWT.
- [ ] Duplicate event does not duplicate grants.
- [ ] Fake provider fully tests Local.
- [ ] No real provider account required.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not select/activate real payments or log secrets.

### Output

Tested payment webhook boundary.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`feat(payment): add signed webhook adapter boundary` — Task P5-T009.

### Next

P5-T010.

## P5-T010 — Implement Commerce Resource Queries and Order 360

Status: pending  
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: api-aggregation  
Track: B/C  
Parallel Safe: yes

### Architecture References

- Main §11 Admin Query
- §15.5 Order 360
- §13 redaction

### Dependencies

P5-T004,P5-T007,P5-T008.

### Goal

Expose Orders, Payments, Refunds/Exceptions, and aggregate Order overview by role.

### Inputs

Commerce facts/grants/audit.

### Files To Inspect

- Admin query framework
- Commerce contracts

### Files To Create

- Commerce query/overview handlers/tests

### Files To Modify

- admin-client Data Provider mappings

### Implementation Steps

1. Implement server pagination/filter/search/sort.
2. Aggregate order/items/snapshots/payment/events/grants/refunds/exceptions/audit.
3. Apply Finance/Support/Admin redaction.
4. Return no raw payment credentials/events.
5. Test URL mapping.

### Commands

```bash
pnpm test:contract
pnpm functions:test -- commerce-query
pnpm test:integration -- order-overview
```

### Tests

Role projections, filters/pages, multi-item relations, deleted user, sensitive-field rejection.

### Acceptance Criteria

- [ ] Order overview links each item to its Grant/refund.
- [ ] Browser needs one overview request.
- [ ] Role redaction is server-side.
- [ ] Tests pass.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not derive final states in Admin UI.

### Output

Commerce Query and Order 360 API.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`feat(admin-api): add commerce queries and order overview` — Task P5-T010.

### Next

P5-T011.

## P5-T011 — Build Admin Commerce operations and Order 360 UI

Status: pending  
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: frontend-security  
Track: E/F  
Parallel Safe: no

### Architecture References

- Main §15 Commerce/Order 360
- Admin AGENTS §§38,42,56

### Dependencies

P5-T006,P5-T007,P5-T008,P5-T010.

### Goal

Deliver role-aware Orders/Payments/Refunds/Exceptions UI and safe verify/refund actions.

### Inputs

Commerce Data Provider/Commands and Ant components.

### Files To Inspect

- commerce module
- DangerousActionDialog

### Files To Create

- Commerce pages
- OrderTimeline/MoneyDisplay usage
- tests

### Files To Modify

- module registry/nav

### Implementation Steps

1. Build server-driven lists and Order 360.
2. Use MoneyDisplay and exact timestamps.
3. Implement verify/refund/chargeback actions via command hooks.
4. Require order-number confirmation where configured.
5. Show audit/request trace and invalidate queries.

### Commands

```bash
pnpm --filter admin test -- commerce
pnpm test:e2e --grep ADM-D
pnpm --filter admin build
```

### Tests

Owner/Admin/Support/Finance UI/API matrix, partial/full refund, retry/double click, errors/timeline.

### Acceptance Criteria

- [ ] Support cannot refund; Finance can per matrix.
- [ ] No `amount/100` scattered formatting.
- [ ] No status edit UI.
- [ ] Tests pass.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not expose provider secrets/raw payloads or infer payment state.

### Output

Admin Commerce operations.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`feat(admin): add commerce operations and order overview` — Task P5-T011.

### Next

P5-T012.

## P5-T012 — Run complete Commerce E2E and resilience scenarios

Status: pending  
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: e2e-security  
Track: F  
Parallel Safe: no

### Architecture References

- Main §16.4 Admin E2E
- §12 Commerce transactions

### Dependencies

P5-T009,P5-T011.

### Goal

Prove order→payment→multi-item grants→partial/full refund→chargeback→Audit end to end.

### Inputs

Fake provider, Admin UI, role fixtures.

### Files To Inspect

- Commerce tests
- Playwright orchestration

### Files To Create

- P5 cross-system E2E/resilience specs

### Files To Modify

- fixtures

### Implementation Steps

1. Create multi-item test order.
2. Deliver signed paid event and verify grants.
3. Apply partial compensation and full item return.
4. Apply chargeback scenario.
5. Exercise duplicate/out-of-order events and role denials.
6. Verify Audit/requestId.

### Commands

```bash
pnpm test:e2e --grep P5
pnpm test:integration -- commerce-resilience
pnpm secrets:check
```

### Tests

Full flow plus retries/concurrency/rollback/forbidden roles.

### Acceptance Criteria

- [ ] All flows pass headlessly.
- [ ] No duplicate or partial fulfillment.
- [ ] Refund/Grant trace is exact per item.
- [ ] No secret leaks.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not require real payment or manual verification.

### Output

Automated Commerce proof.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`test(e2e): cover commerce fulfillment and refunds` — Task P5-T012.

### Next

P5-T013.

## P5-T013 — Execute Commerce and Admin D quality gate

Status: pending  
Phase: P5 — Commerce + Admin D  
Execution: AUTONOMOUS  
Type: quality-gate  
Track: F/G  
Parallel Safe: no

### Architecture References

- Main §19 Commerce/Admin D acceptance
- §16 Quality

### Dependencies

P5-T001, P5-T002, P5-T003, P5-T004, P5-T005, P5-T006, P5-T007, P5-T008, P5-T009, P5-T010, P5-T011, P5-T012.

### Goal

Run full clean verification and create PHASE-05 checkpoint.

### Inputs

All P5 outputs.

### Files To Inspect

- Commerce migrations/APIs/UI/tests
- progress/ledger

### Files To Create

- `checkpoints/PHASE-05.md`

### Files To Modify

- `PROGRESS.md`
- `TASK_LEDGER.md`

### Implementation Steps

1. Run clean platform verify and P5 E2E.
2. Run webhook/security/secret scans.
3. Repair/rerun all.
4. Record evidence and deferred real provider decision.

### Commands

```bash
pnpm platform:verify
pnpm test:e2e --grep P5
git status --short
```

### Tests

All quality categories.

### Acceptance Criteria

- [ ] All applicable checks PASS.
- [ ] Multi-item/refund/idempotency evidence recorded.
- [ ] No real payment dependency.
- [ ] Architecture Deviations None or approved.
- [ ] Human interactions used: 0.

### Failure Recovery

Diagnose, repair within the approved Commerce model, rerun focused and full task tests. Raise an Architecture Blocker only for an actual model contradiction.

### Do Not

Do not treat fake provider as production cutover.

### Output

PHASE-05 checkpoint.

### Human Gate

None. Use manual-channel fixtures and a Local fake provider; real commercial/payment decisions are deferred to HG-002.

### Commit

`chore(checkpoint): complete commerce operations` — Task P5-T013.

### Next

P6-T001.
