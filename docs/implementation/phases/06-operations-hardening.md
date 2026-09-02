# Phase P6 — Operations Efficiency and Hardening

Goal: complete Admin Phase E, deletion/retention operations, observability, security, resilience, documentation, and the Local release candidate. Human Interaction Budget: **0**.

## P6-T001 — Complete retryable account deletion and anonymization worker

Status: completed
Phase: P6 — Operations Hardening  
Execution: AUTONOMOUS  
Type: domain-operations  
Track: A/B/F  
Parallel Safe: yes

### Architecture References

- Main §12.5 deletion
- §17.5 retention
- §15 Customers

### Dependencies

P4-T008,P5-T013.

### Goal

Complete Local cross-system deletion processing with idempotent DB/Auth steps and Admin exception visibility.

### Inputs

Deletion requests, Supabase Local Auth, Commerce retention facts.

### Files To Inspect

- deletion workflow
- retention table

### Files To Create

- worker implementation
- retry/failure tests

### Files To Modify

- Admin deletion query/command UI as needed

### Implementation Steps

1. Implement due-request lock/processing.
2. Revoke sessions/grants and anonymize profile/feedback in DB transaction.
3. Call Local Auth admin soft delete/anonymize idempotently.
4. Retain/de-identify Commerce/Audit facts.
5. Expose failed attempts without sensitive error text.

### Commands

```bash
pnpm functions:test -- deletion-worker
pnpm test:integration -- account-deletion
```

### Tests

Success, Auth failure/retry, duplicate worker, retained financial facts, no old Grant revival.

### Acceptance Criteria

- [x] Workflow recovers after injected external failure.
- [x] PII removed per architecture.
- [x] Required facts remain pseudonymous.
- [x] Tests pass.

### Failure Recovery

Use test evidence to fix the smallest in-scope defect, rerun focused checks and then the complete task commands. Preserve important failure history in progress/checkpoints.

### Do Not

Do not hardcode legal retention days or delete all rows.

### Output

Recoverable deletion processing.

Delivered through `supabase/functions/account-deletion-worker/index.ts` and
`supabase/migrations/20260902230000_account_deletion_worker.sql`. Auth is
anonymized and banned before the database completion transaction; external
failures record only stable retry codes. The database transaction revokes active
Grants, removes Platform Sessions, anonymizes Feedback, detaches Orders while
retaining customer references, disables any Admin membership, clears audit IP
hashes through a narrowly controlled scrub path, and completes idempotently.

Verification: database 969/969, account-deletion worker integration 3/3, full
integration 47/47, function smoke 5/5, typecheck, lint, format, boundaries, and
secret scan all passed.

### Human Gate

None. Local hardening and optional visual review never block autonomous execution.

### Commit

`feat(identity): complete account deletion processing` — Task P6-T001. Implementation commit: `2212c7f`.

### Next

P6-T002.

## P6-T002 — Implement retention and cleanup jobs with safe defaults

Status: completed
Phase: P6 — Operations Hardening  
Execution: AUTONOMOUS  
Type: operations  
Track: A/B/F  
Parallel Safe: yes

### Architecture References

- Main §17.5 data retention
- §8.8 idempotency expiry

### Dependencies

P6-T001.

### Goal

Create explicit configurable cleanup for expired sessions, minimized security context, and idempotency responses without touching retained business facts.

### Inputs

Retention categories and nonproduction defaults.

### Files To Inspect

- all timestamped tables
- environment config

### Files To Create

- cleanup functions/jobs/tests
- retention config docs

### Files To Modify

- function schedule entrypoints

### Implementation Steps

1. Define config keys, no production legal values.
2. Delete/reduce only architecture-approved ephemeral fields.
3. Make jobs idempotent/batched.
4. Audit job result summaries without PII.
5. Test dry-run and bounds.

### Commands

```bash
pnpm db:test -- retention
pnpm functions:test -- cleanup
```

### Tests

Boundary dates, retries, batching, protected orders/grants/audit, dry-run.

### Acceptance Criteria

- [x] Retained facts are untouched.
- [x] Jobs are bounded/idempotent.
- [x] Config is documented.
- [x] Tests pass.

### Failure Recovery

Use test evidence to fix the smallest in-scope defect, rerun focused checks and then the complete task commands. Preserve important failure history in progress/checkpoints.

### Do Not

Do not invent jurisdiction retention or require queue/Redis.

### Output

Safe retention jobs delivered through
`supabase/functions/retention-cleanup/index.ts` and
`supabase/migrations/20260903010000_retention_cleanup.sql`. The service-only
worker validates environment configuration, uses Local-safe defaults, and
passes server-computed cutoffs to a bounded database function. The function
supports dry-run, `FOR UPDATE SKIP LOCKED` batching, expired session removal,
aged security-hash clearing, and expired idempotency-response scrubbing while
retaining referenced response identities and all business facts.

Configuration is documented in `LOCAL_DEVELOPMENT.md` and both environment
examples. Verification: database 997/997, root tests 117/117, integration
51/51, function smoke 6/6, type generation stability, typecheck, lint, format,
build, boundaries, secrets, and failure-propagation checks all passed.

### Human Gate

None. Local hardening and optional visual review never block autonomous execution.

### Commit

`feat(operations): add bounded retention cleanup` — Task P6-T002. Implementation commit: `dbfad01`.

### Next

P6-T003.

## P6-T003 — Implement request context, metrics, and safe structured logging

Status: completed
Phase: P6 — Operations Hardening  
Execution: AUTONOMOUS  
Type: observability  
Track: B/G/F  
Parallel Safe: yes

### Architecture References

- Main §17.1–17.3 observability
- §13 secrets

### Dependencies

P5-T013.

### Goal

Standardize request_id/user/app/route/result/latency telemetry and phase-appropriate metrics/alerts without sensitive content.

### Inputs

All Edge routers and domain outcomes.

### Files To Inspect

- shared middleware
- log filters

### Files To Create

- telemetry module/tests
- metric/alert docs

### Files To Modify

- all function entrypoints

### Implementation Steps

1. Generate/propagate requestId once.
2. Add safe structured context.
3. Emit login/access/redemption/payment/admin metrics.
4. Define alert thresholds as configurable nonproduction defaults.
5. Test redaction for tokens/cookies/codes/payment data.

### Commands

```bash
pnpm functions:test -- telemetry
pnpm secrets:check
pnpm test:integration -- request-id
```

### Tests

Request propagation, all error classes, redaction, metric labels bounded, logger failure behavior.

### Acceptance Criteria

- [x] Every API response has requestId.
- [x] No sensitive value logged.
- [x] Required metrics exist.
- [x] Tests pass.

### Failure Recovery

Use test evidence to fix the smallest in-scope defect, rerun focused checks and then the complete task commands. Preserve important failure history in progress/checkpoints.

### Do Not

Do not add a heavy observability platform dependency.

### Output

Safe platform telemetry delivered through the shared
`supabase/functions/_shared/telemetry.ts` boundary. All six Edge Function
entrypoints generate one trace ID, inject it into the internal request, ensure
the response header/body carries it, normalize routes, classify stable result
codes, and emit bounded JSON telemetry. Logger failures are swallowed, and no
response bodies or credential-bearing values are logged. Metric names and
nonproduction alert defaults are documented in `docs/implementation/TELEMETRY.md`.

Verification: root tests 120/120, integration 54/54, function smoke 6/6,
typecheck, lint, format, build, boundaries, secrets, and failure-propagation
checks all passed.

### Human Gate

None. Local hardening and optional visual review never block autonomous execution.

### Commit

`feat(observability): add request context and metrics` — Task P6-T003. Implementation commit: `509e46c`.

### Next

P6-T004.

## P6-T004 — Finalize System Health and actionable Admin dashboard

Status: completed
Phase: P6 — Operations Hardening  
Execution: AUTONOMOUS  
Type: api-frontend  
Track: B/E  
Parallel Safe: yes

### Architecture References

- Main §15.4 Overview/System Health
- §17 metrics
- Admin AGENTS §50

### Dependencies

P6-T003,P5-T010.

### Goal

Provide safe health/operational summaries and drill-down dashboard cards.

### Inputs

Telemetry, existing Query APIs, role matrix.

### Files To Inspect

- system health endpoint
- Admin overview

### Files To Create

- health/overview aggregation tests
- dashboard cards/drill-down specs

### Files To Modify

- Admin overview module/contracts

### Implementation Steps

1. Expose component health without secrets/topology internals.
2. Aggregate actionable counts from existing facts.
3. Link cards to URL-filtered lists.
4. Apply role filters.
5. Handle stale/partial service state.

### Commands

```bash
pnpm functions:test -- system-health
pnpm --filter admin test -- overview
pnpm test:e2e --grep DASHBOARD
```

### Tests

Role cards, drill-down URLs, partial failure, safe payload, no arbitrary BI/query.

### Acceptance Criteria

- [x] Every important card drills down.
- [x] No free-form SQL/BI exists.
- [x] Health payload is safe.
- [x] Tests pass.

### Failure Recovery

Use test evidence to fix the smallest in-scope defect, rerun focused checks and then the complete task commands. Preserve important failure history in progress/checkpoints.

### Do Not

Do not prioritize decorative charts or add second analytics store.

### Output

Actionable operations dashboard delivered through the fixed `/v1/admin/overview` query and the
existing System Health endpoint. The role-filtered aggregate returns only bounded counts and
allowlisted drill-down paths; Finance receives chargeback visibility but no feedback card. Admin
Overview loads independently from health so a partial service failure remains visible and
actionable. A dedicated Feedback list route makes the open-feedback card directly usable.

Verification: database 1014/1014, root tests 124/124, integration 58/58, Admin E2E 6/6 on
isolated local ports, function smoke, typecheck, lint, format, build, boundaries, and secret scan
passed. The local E2E harness now accepts `PLAYWRIGHT_BASE_URL` and
`PLAYWRIGHT_ADMIN_BASE_URL` to avoid unrelated local port occupants.

### Human Gate

None. Local hardening and optional visual review never block autonomous execution.

### Commit

`feat(admin): finalize actionable operations dashboard` — Task P6-T004. Implementation commit: `116a8b8`.

### Next

P6-T005.

## P6-T005 — Implement structured saved filters and URL-state conventions

Status: completed
Phase: P6 — Operations Hardening  
Execution: AUTONOMOUS  
Type: frontend  
Track: E  
Parallel Safe: yes

### Architecture References

- Admin AGENTS §§25,49
- Main §15 Admin efficiency

### Dependencies

P6-T004.

### Goal

Add safe structured filter presets and consistent deep-linkable list state.

### Inputs

Refine Data Provider and list modules.

### Files To Inspect

- all Admin lists
- filter contracts

### Files To Create

- saved filter schema/storage adapter/tests

### Files To Modify

- list modules

### Implementation Steps

1. Define resource-specific structured filter schemas.
2. Keep pagination/filter/search/sort in URL.
3. Store only non-sensitive structured presets in local preference storage unless an approved API exists.
4. Reject arbitrary expressions.
5. Test refresh/back/bookmark.

### Commands

```bash
pnpm --filter admin test -- filters
pnpm test:e2e --grep FILTERS
```

### Tests

Round trip URL, invalid preset, role/resource isolation, no SQL/expression, refresh/back/forward.

### Acceptance Criteria

- [x] Only allowlisted filters persist.
- [x] Deep links restore state.
- [x] No sensitive values are stored.
- [x] Tests pass.

### Failure Recovery

Use test evidence to fix the smallest in-scope defect, rerun focused checks and then the complete task commands. Preserve important failure history in progress/checkpoints.

### Do Not

Do not add a saved-filter database table without architecture need.

### Output

Safe Admin productivity filters delivered through the resource-scoped local
preference adapter in `apps/admin/src/providers/saved-filters.ts`. Presets are
limited to an explicit resource/status allowlist, capped at twenty entries per
resource, sanitized on read, and never include search text, arbitrary filter
expressions, SQL, credentials, or customer content. The Admin Refine shell now
registers its resources and supplies a React Router adapter so Refine's
pagination, filter, search, and sort state is represented in URL query state
and restored on deep links and browser history navigation. No saved-filter
database table was added.

Verification: Admin tests 12/12, FILTERS E2E 1/1, Admin operations E2E 7/7,
root tests 127/127, integration 58/58, contracts 15/15, Admin Client 17/17,
typecheck, lint, format, workspace build, boundaries, and secret scan passed.

### Human Gate

None. Local hardening and optional visual review never block autonomous execution.

### Commit

`feat(admin): add structured saved filters` — Task P6-T005. Implementation
commit: `6d84e59`.

### Next

P6-T006.

## P6-T006 — Harden accessibility, performance, and error recovery

Status: completed
Phase: P6 — Operations Hardening  
Execution: AUTONOMOUS  
Type: quality  
Track: E/F  
Parallel Safe: yes

### Architecture References

- Main §19 Admin E
- Admin AGENTS §§34–48

### Dependencies

P6-T004,P6-T005.

### Goal

Make core Admin operations keyboard-accessible, performant on realistic datasets, and resilient to partial errors.

### Inputs

All Admin pages and seeded large fixtures.

### Files To Inspect

- Admin components/routes
- bundle/test reports

### Files To Create

- a11y/performance tests
- large fixture generator

### Files To Modify

- pages/components/query settings

### Implementation Steps

1. Run automated accessibility checks and keyboard flows.
2. Test server pagination on realistic counts.
3. Measure bundle/routes and lazy-load modules where useful.
4. Test retry/error boundaries and preserved form input.
5. Fix N+1/browser fan-out.

### Commands

```bash
pnpm --filter admin test:a11y
pnpm --filter admin build
pnpm test:e2e --grep RESILIENCE
```

### Tests

A11y rules, keyboard dangerous dialog, load/empty/error, large list latency budgets, bundle thresholds.

### Acceptance Criteria

- [x] No critical accessibility violations.
- [x] Lists remain server-driven.
- [x] Failures recover without losing useful input.
- [x] Build budgets pass.

### Failure Recovery

Use test evidence to fix the smallest in-scope defect, rerun focused checks and then the complete task commands. Preserve important failure history in progress/checkpoints.

### Do Not

Do not optimize by weakening validation/security.

### Output

Accessible resilient Admin delivered through bounded React Query retry for
server-driven lists, accessible in-place retry controls that preserve form
values, independent Overview/System Health recovery actions, and lazy-loaded
route modules. The shared ErrorState accepts an optional action while retaining
its live-region semantics. A11Y keyboard checks cover the main landmark,
headings, search/status/saved-view controls, and tab order; RESILIENCE covers a
temporary list failure, recovery, and preserved search input. The production
build now emits route-specific chunks; the existing Vite large-vendor-chunk
notice remains non-blocking.

Verification: Admin tests 12/12, Admin operations E2E 9/9 including A11Y 1/1
and RESILIENCE 1/1, root tests 127/127, integration 58/58, contracts 15/15,
Admin Client 17/17, typecheck, lint, format, workspace build, boundaries, and
secret scan passed.

### Human Gate

None. Local hardening and optional visual review never block autonomous execution.

### Commit

`perf(admin): harden accessibility and resilience` — Task P6-T006. Implementation
commit: `f5cce39`.

### Next

P6-T007.

## P6-T007 — Run full security and architecture-boundary audit

Status: pending  
Phase: P6 — Operations Hardening  
Execution: AUTONOMOUS  
Type: security-audit  
Track: F  
Parallel Safe: no

### Architecture References

- Main §13 Security boundaries
- §16.5 security tests
- root/admin AGENTS prohibitions

### Dependencies

P6-T001, P6-T002, P6-T003, P6-T004, P6-T005, P6-T006.

### Goal

Prove no direct DB/Admin bypass, secret leak, cross-role escalation, unsafe function, or architecture-forbidden dependency exists.

### Inputs

Complete Local implementation.

### Files To Inspect

- dependency graph
- migrations/grants/functions
- bundles/logs
- all clients

### Files To Create

- security audit report/tests

### Files To Modify

- scanners/tests and defects only

### Implementation Steps

1. Scan imports/bundles/env/logs.
2. Enumerate DB grants/RLS/functions/search_path.
3. Replay direct API and client-manipulation attacks.
4. Check code/code-hash/payment/session redaction.
5. Check forbidden infrastructure/frameworks.

### Commands

```bash
pnpm secrets:check
pnpm boundaries:check
pnpm rls:test
pnpm test:security
pnpm platform:verify
```

### Tests

Negative matrix across anon/user/Admin roles and direct DB/API attempts.

### Acceptance Criteria

- [ ] No critical/high finding remains.
- [ ] Admin bundle contains no secret/Supabase Data access.
- [ ] All privileged functions are constrained/tested.
- [ ] Report links evidence.

### Failure Recovery

Use test evidence to fix the smallest in-scope defect, rerun focused checks and then the complete task commands. Preserve important failure history in progress/checkpoints.

### Do Not

Do not waive findings without approved documented reason.

### Output

Local security audit evidence.

### Human Gate

None. Local hardening and optional visual review never block autonomous execution.

### Commit

`test(security): complete platform boundary audit` — Task P6-T007.

### Next

P6-T008.

## P6-T008 — Run complete release-candidate E2E journey

Status: pending  
Phase: P6 — Operations Hardening  
Execution: AUTONOMOUS  
Type: e2e  
Track: F  
Parallel Safe: no

### Architecture References

- Main §16 E2E
- §21 acceptance criteria
- Admin AGENTS §57

### Dependencies

P6-T007.

### Goal

Execute the full Local release journey from login through Catalog, redemption, entitlements, Commerce, refund, deletion, and Audit.

### Inputs

Complete Local platform and all role fixtures.

### Files To Inspect

- all phase E2E suites
- master acceptance criteria

### Files To Create

- release-candidate E2E orchestrator/report

### Files To Modify

- fixtures/test orchestration

### Implementation Steps

1. Reset once and run deterministic end-to-end journey.
2. Include four Admin roles and normal user.
3. Exercise failure/retry/concurrency side scenarios.
4. Validate requestId→Audit traces.
5. Keep artifact redaction.

### Commands

```bash
pnpm db:reset
pnpm test:e2e --grep RELEASE-CANDIDATE
pnpm test:integration -- resilience
```

### Tests

Full architecture user/Admin/Commerce/security journey.

### Acceptance Criteria

- [ ] All journeys pass headlessly.
- [ ] No test order dependency remains.
- [ ] Audit trace is complete.
- [ ] Artifacts are safe.

### Failure Recovery

Use test evidence to fix the smallest in-scope defect, rerun focused checks and then the complete task commands. Preserve important failure history in progress/checkpoints.

### Do Not

Do not substitute manual UX review for E2E.

### Output

Local release-candidate proof.

### Human Gate

None. Local hardening and optional visual review never block autonomous execution.

### Commit

`test(e2e): add platform release candidate journey` — Task P6-T008.

### Next

P6-T009.

## P6-T009 — Synchronize implementation documentation and runbooks

Status: pending  
Phase: P6 — Operations Hardening  
Execution: AUTONOMOUS  
Type: documentation  
Track: G  
Parallel Safe: yes

### Architecture References

- Main §18 release
- root AGENTS §41 Documentation
- Master completion definition

### Dependencies

P6-T007,P6-T008.

### Goal

Document actual commands, environment variables, API generation, Local recovery, and operational runbooks without changing architecture to match defects.

### Inputs

Verified implementation and test commands.

### Files To Inspect

- all docs/config/scripts
- architecture/change log

### Files To Create

- Local development/runbook/API generation/security response docs

### Files To Modify

- `.env.example`
- README/progress references

### Implementation Steps

1. Document one-command rebuild and troubleshooting.
2. Document no-secret environment setup.
3. Document migration/function/app release order.
4. Document incident/recovery and code-export handling.
5. Cross-link architecture/task/commit.

### Commands

```bash
pnpm docs:check
pnpm platform:verify
```

### Tests

Link/code-block/command checks and fresh-reader dry run where automated.

### Acceptance Criteria

- [ ] Docs match actual commands.
- [ ] No secret/sample looks production-valid.
- [ ] Architecture remains unchanged unless approved.
- [ ] Docs checks pass.

### Failure Recovery

Use test evidence to fix the smallest in-scope defect, rerun focused checks and then the complete task commands. Preserve important failure history in progress/checkpoints.

### Do Not

Do not hide known limitations or rewrite history.

### Output

Implementation-aligned docs/runbooks.

### Human Gate

None. Local hardening and optional visual review never block autonomous execution.

### Commit

`docs(platform): add implementation and operations runbooks` — Task P6-T009.

### Next

P6-T010.

## P6-T010 — Execute Operations Hardening quality gate

Status: pending  
Phase: P6 — Operations Hardening  
Execution: AUTONOMOUS  
Type: quality-gate  
Track: F/G  
Parallel Safe: no

### Architecture References

- Main §19 Admin E
- §21 acceptance criteria
- §18.5 migration capability

### Dependencies

P6-T001, P6-T002, P6-T003, P6-T004, P6-T005, P6-T006, P6-T007, P6-T008, P6-T009.

### Goal

Produce PHASE-06 Local release-candidate checkpoint and authorize Staging tasks.

### Inputs

All Local implementation/evidence.

### Files To Inspect

- security report
- E2E report
- progress/ledger

### Files To Create

- `checkpoints/PHASE-06.md`

### Files To Modify

- `PROGRESS.md`
- `TASK_LEDGER.md`

### Implementation Steps

1. Run clean full verify/security/E2E/build/docs.
2. Verify migration boundaries and no generated drift.
3. Repair/rerun.
4. Record Local completion, limitations, deferred commercial items, Git range.

### Commands

```bash
pnpm platform:verify
pnpm test:security
pnpm test:e2e --grep RELEASE-CANDIDATE
pnpm docs:check
git status --short
```

### Tests

Every applicable Definition-of-Done category.

### Acceptance Criteria

- [ ] All Local DoD checks PASS.
- [ ] Security findings are closed.
- [ ] Architecture Deviations None or approved.
- [ ] Human interactions used: 0.
- [ ] HG-001 remains untriggered until P7 environment inspection.

### Failure Recovery

Use test evidence to fix the smallest in-scope defect, rerun focused checks and then the complete task commands. Preserve important failure history in progress/checkpoints.

### Do Not

Do not enter Staging with any red applicable check.

### Output

PHASE-06 checkpoint and Local release candidate.

### Human Gate

None. Local hardening and optional visual review never block autonomous execution.

### Commit

`chore(checkpoint): complete local operations hardening` — Task P6-T010.

### Next

P7-T001.
