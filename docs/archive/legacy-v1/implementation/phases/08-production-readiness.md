# Phase P8 — Production Readiness and Explicit Release Gates

Goal: prepare an auditable Production release, obtain explicit approvals, execute only approved mutations, and distinguish implementation completeness from public cutover. Production Human Interaction Budget: **explicit gates only**.

## P8-T001 — Resolve commercial configuration freeze when real sale is planned

Status: pending  
Phase: P8 — Production Readiness  
Execution: HUMAN_GATE  
Type: product-gate  
Track: Product/G  
Parallel Safe: no

### Architecture References

- Main §22 Product Decisions
- Human Gates HG-002

### Dependencies

P7-T009.

### Goal

Obtain one coherent set of commercial promises only if release enables real sales.

### Inputs

Architecture decision list and Staging test configuration.

### Files To Inspect

- HG-002
- current product/retention/payment configs

### Files To Create

- approved commercial configuration record/ADR link if needed

### Files To Modify

- `HUMAN_GATES.md`
- `PROGRESS.md`

### Implementation Steps

1. If release has no real sale, mark deferred/skipped and keep test values.
2. Identify only unresolved commercial decisions.
3. Present them together with implementation impact, without asking technical questions.
4. Record approved values/policies in the designated non-secret configuration/docs.
5. Re-run affected contract/state tests.

### Commands

```bash
pnpm production:commercial-preflight
```

### Tests

Configuration completeness and regression tests using approved values.

### Acceptance Criteria

- [ ] Gate is resolved or explicitly deferred.
- [ ] No Agent-invented price/promise/policy exists.
- [ ] Affected tests pass.
- [ ] Decision record is linked.

### Failure Recovery

Do not improvise around a Production failure. Follow the approved stop, rollback, or forward-fix plan; preserve evidence and update progress/gates before any retry.

### Do Not

Do not block technical readiness when real sales are out of scope.

### Output

Frozen or deferred commercial configuration.

### Human Gate

HG-002; maximum one consolidated interaction and only for genuine commercial commitments.

### Commit

`docs(product): record commercial release decisions` — Task P8-T001.

### Next

P8-T002.

## P8-T002 — Inspect Production authorization/resources without mutation

Status: pending  
Phase: P8 — Production Readiness  
Execution: AUTONOMOUS  
Type: discovery  
Track: G  
Parallel Safe: no

### Architecture References

- Human Gates HG-003
- Main §18 Production
- Agent Rules §6

### Dependencies

P7-T009.

### Goal

Determine existing Production access/resource/config readiness without creating or changing anything.

### Inputs

Current scoped CLI/account sessions and required variable names.

### Files To Inspect

- Production project/hosting/DNS status read-only
- Staging deployment manifest

### Files To Create

- `docs/implementation/PRODUCTION_BASELINE.md`

### Files To Modify

- `HUMAN_GATES.md`
- `PROGRESS.md`

### Implementation Steps

1. Check Production resources and permissions read-only.
2. Check secret variable presence without values.
3. Verify environment isolation and intended domains.
4. List all missing account/resource/secret authorization together.
5. Mark HG-003 skipped or ready.

### Commands

```bash
pnpm production:preflight --check-only --no-mutate
```

### Tests

Preflight redaction and environment identity checks.

### Acceptance Criteria

- [ ] No Production state changed.
- [ ] Baseline is complete and safe.
- [ ] HG-003 has one clear state.
- [ ] Missing items are batched.

### Failure Recovery

Do not improvise around a Production failure. Follow the approved stop, rollback, or forward-fix plan; preserve evidence and update progress/gates before any retry.

### Do Not

Do not create projects, set secrets, migrate, deploy, or change DNS.

### Output

Production capability baseline.

### Human Gate

None yet; only prepare HG-003 if missing.

### Commit

`docs(production): record readiness baseline` — Task P8-T002.

### Next

P8-T003 or P8-T004.

## P8-T003 — Resolve Production infrastructure and secret authorization

Status: pending  
Phase: P8 — Production Readiness  
Execution: HUMAN_GATE  
Type: human-gate  
Track: G  
Parallel Safe: no

### Architecture References

- Human Gates HG-003
- Agent Rules §5

### Dependencies

P8-T002.

### Goal

Obtain all unavailable Production authorization/resources/named secret configuration in one interaction.

### Inputs

Production baseline and missing-item bundle.

### Files To Inspect

- HG-003 evidence

### Files To Create

- No secret-bearing source files.

### Files To Modify

- `HUMAN_GATES.md`
- `PROGRESS.md`
- `TASK_LEDGER.md`

### Implementation Steps

1. If all capabilities exist, mark skipped.
2. Otherwise set READY and ask once for scoped authorization/resource creation/secret-manager variable configuration.
3. Never request values in chat.
4. Verify access/presence without outputting values.
5. Mark resolved and continue.

### Commands

```bash
pnpm production:preflight --check-only --no-mutate
```

### Tests

Read-only preflight after resolution.

### Acceptance Criteria

- [ ] HG-003 skipped or resolved.
- [ ] Required Production capabilities exist.
- [ ] No secret disclosed/committed.
- [ ] Only one interaction used.

### Failure Recovery

Do not improvise around a Production failure. Follow the approved stop, rollback, or forward-fix plan; preserve evidence and update progress/gates before any retry.

### Do Not

Do not treat access authorization as deploy approval.

### Output

Production access readiness.

### Human Gate

HG-003; wait only when missing access/resources/secrets are proven.

### Commit

`docs(gate): resolve production infrastructure authorization` — Task P8-T003.

### Next

P8-T004.

## P8-T004 — Prepare production release, migration, smoke, and recovery dossier

Status: pending  
Phase: P8 — Production Readiness  
Execution: AUTONOMOUS  
Type: release-planning  
Track: A/B/G/F  
Parallel Safe: no

### Architecture References

- Main §18.3–18.5
- Human Gates HG-004
- §17 production protection

### Dependencies

P8-T001 completed with HG-002 `resolved`, `deferred`, or `skipped`; P8-T003 completed with HG-003 `skipped` or `resolved`.

### Goal

Produce the exact evidence package required for production approval without mutating Production.

### Inputs

Staging-proven immutable artifacts and Production baseline.

### Files To Inspect

- PHASE-07 checkpoint
- migrations/artifacts
- backup capability

### Files To Create

- production deployment plan
- migration plan
- smoke checklist
- rollback/forward-fix plan
- stop conditions

### Files To Modify

- release manifest

### Implementation Steps

1. Pin Git SHA/checksums and deployment order.
2. Diff expected Production migration state read-only.
3. Verify backup/recovery-point method.
4. Define commands/operators/timeouts/stop conditions.
5. Define postdeploy security/Audit checks and rollback limits.

### Commands

```bash
pnpm production:release-dossier --no-mutate
pnpm production:preflight --check-only --no-mutate
```

### Tests

Dossier completeness, artifact checksums, migration dry-run against disposable clone/schema.

### Acceptance Criteria

- [ ] Every planned mutation is enumerated.
- [ ] Recovery/forward-fix is executable.
- [ ] Staging evidence is linked.
- [ ] No Production mutation occurred.

### Failure Recovery

Do not improvise around a Production failure. Follow the approved stop, rollback, or forward-fix plan; preserve evidence and update progress/gates before any retry.

### Do Not

Do not apply migrations/deploy/change secrets.

### Output

Production release dossier.

### Human Gate

None; this is autonomous preparation for HG-004.

### Commit

`docs(release): prepare production deployment dossier` — Task P8-T004.

### Next

P8-T005.

## P8-T005 — Obtain explicit production migration and deployment approval

Status: pending  
Phase: P8 — Production Readiness  
Execution: HUMAN_GATE  
Type: production-gate  
Track: G  
Parallel Safe: no

### Architecture References

- Human Gates HG-004
- Agent Rules Production prohibitions

### Dependencies

P8-T004.

### Goal

Present the complete dossier and receive explicit authorization for exact Production mutations.

### Inputs

Production release dossier and Staging evidence.

### Files To Inspect

- all dossier documents
- HG-004

### Files To Create

- approval record reference

### Files To Modify

- `HUMAN_GATES.md`
- `PROGRESS.md`
- `TASK_LEDGER.md`

### Implementation Steps

1. Set HG-004 READY with exact artifact/migration/resource scope.
2. Present impact, evidence, backup, rollback, smoke, and stop conditions.
3. Wait for explicit approval.
4. If scope changes, regenerate dossier; do not infer approval.
5. Record approval and permitted window/scope.

### Commands

```bash
pnpm production:release-dossier --verify
```

### Tests

Dossier verification only.

### Acceptance Criteria

- [ ] Explicit approval is recorded for exact scope.
- [ ] No mutation occurs before approval.
- [ ] Gate status becomes resolved.
- [ ] Any rejection leaves Production unchanged.

### Failure Recovery

Do not improvise around a Production failure. Follow the approved stop, rollback, or forward-fix plan; preserve evidence and update progress/gates before any retry.

### Do Not

Do not treat prior infrastructure authorization as deployment approval.

### Output

Resolved mandatory HG-004 or safely paused release.

### Human Gate

HG-004 is mandatory for the first Production deployment.

### Commit

`docs(gate): record production deployment approval` — Task P8-T005.

### Next

P8-T006 after approval only.

## P8-T006 — Execute approved Production deployment and immediate smoke

Status: pending  
Phase: P8 — Production Readiness  
Execution: AUTONOMOUS  
Type: production-deployment  
Track: A/B/D/E/G/F  
Parallel Safe: no

### Architecture References

- Main §18.3 release order
- approved HG-004 dossier

### Dependencies

P8-T005 completed and HG-004 `resolved` with explicit approval.

### Goal

Apply only the approved database/functions/apps scope and stop safely on defined conditions.

### Inputs

Approved artifacts/commands/window.

### Files To Inspect

- approval scope
- live preflight/backup status

### Files To Create

- production deployment result and smoke report

### Files To Modify

- progress/ledger

### Implementation Steps

1. Reconfirm artifact checksums, target identity, backup/recovery point.
2. Apply migrations and DB tests.
3. Deploy functions then account/admin clients in approved order.
4. Run immediate session/catalog/Admin/security smoke.
5. Stop/forward-fix/rollback exactly per dossier on failure.

### Commands

```bash
pnpm production:deploy --approved-manifest "$AISENHUB_APPROVED_MANIFEST"
pnpm production:test:smoke
```

### Tests

Migration status, health, session, exact CORS, Admin session/RBAC, catalog/access, no secret leakage.

### Acceptance Criteria

- [ ] Only approved scope changed.
- [ ] All immediate smoke checks pass or recovery completed.
- [ ] Deployment result is auditable.
- [ ] No DNS/payment cutover occurred unless separately approved.

### Failure Recovery

Do not improvise around a Production failure. Follow the approved stop, rollback, or forward-fix plan; preserve evidence and update progress/gates before any retry.

### Do Not

Do not improvise unapproved migrations, reset data, or expand scope.

### Output

Deployed or safely recovered Production release.

### Human Gate

HG-004 approval must be active and exact.

### Commit

`chore(production): record approved platform deployment` — Task P8-T006.

### Next

P8-T007.

## P8-T007 — Resolve and execute optional DNS/payment cutover

Status: pending  
Phase: P8 — Production Readiness  
Execution: HUMAN_GATE  
Type: production-cutover-gate  
Track: G/Product/F  
Parallel Safe: no

### Architecture References

- Human Gates HG-005
- Main §5 domains
- §11 webhook

### Dependencies

P8-T006 successful.

### Goal

Cut real traffic/payment only with separate explicit approval, or defer while keeping deployed system dark/private.

### Inputs

Healthy Production deployment, DNS/payment cutover plan.

### Files To Inspect

- DNS/TLS/current routes
- payment webhook status
- HG-005

### Files To Create

- cutover/rollback result

### Files To Modify

- `HUMAN_GATES.md`
- `PROGRESS.md`

### Implementation Steps

1. If no launch/real payment is planned, mark deferred and stop here.
2. Prepare exact DNS records/TTL/TLS and payment webhook/signing/monitoring steps.
3. Set HG-005 READY and request explicit approval.
4. After approval, Agent performs authorized changes if credentials permit.
5. Run external smoke/monitoring and revert on stop conditions.

### Commands

```bash
pnpm production:cutover:preflight --no-mutate
pnpm production:cutover --approved
pnpm production:test:external
```

### Tests

DNS/TLS, cookie/CORS, account/admin, signed webhook test mode then approved live check, monitoring.

### Acceptance Criteria

- [ ] Gate is deferred or explicitly approved.
- [ ] Only approved records/payment settings changed.
- [ ] External smoke passes or rollback succeeds.
- [ ] Evidence recorded.

### Failure Recovery

Do not improvise around a Production failure. Follow the approved stop, rollback, or forward-fix plan; preserve evidence and update progress/gates before any retry.

### Do Not

Do not accept real money or change public DNS without HG-005.

### Output

Deferred or completed Production cutover.

### Human Gate

HG-005; optional until public launch, mandatory for real DNS/payment cutover.

### Commit

`chore(production): record approved traffic cutover` — Task P8-T007.

### Next

P8-T008.

## P8-T008 — Finalize production-readiness checkpoint and handoff

Status: pending  
Phase: P8 — Production Readiness  
Execution: AUTONOMOUS  
Type: quality-gate  
Track: F/G  
Parallel Safe: no

### Architecture References

- Master Completion Definition
- Main §21 acceptance

### Dependencies

P8-T004; additionally P8-T006 when deployment was approved/executed, and P8-T007 when cutover was executed or explicitly deferred.

### Goal

Record final implementation/Production status truthfully, including deferred gates, evidence, and next operational work.

### Inputs

Staging checkpoint, release dossier, gate/deploy/cutover outcomes.

### Files To Inspect

- all P8 records
- progress/ledger/human gates

### Files To Create

- `checkpoints/PHASE-08.md`
- release handoff summary

### Files To Modify

- `PROGRESS.md`
- `TASK_LEDGER.md`

### Implementation Steps

1. Verify current environment state read-only.
2. Run applicable postdeploy or readiness checks.
3. Record completed/deferred tasks and gate counts.
4. Link Architecture→Plan→Task→Commit→Tests.
5. Declare implementation complete only if Master DoD/Staging pass; distinguish Production deployed/cutover/deferred.

### Commands

```bash
pnpm production:preflight --check-only --no-mutate
pnpm docs:check
git status --short
```

### Tests

Applicable readiness/postdeploy checks and documentation trace validation.

### Acceptance Criteria

- [ ] Checkpoint states exact Production status.
- [ ] No failed/skipped applicable check is hidden.
- [ ] Human interventions are counted/purposed.
- [ ] Architecture Deviations None or approved.
- [ ] Progress/ledger/gates are synchronized.

### Failure Recovery

Do not improvise around a Production failure. Follow the approved stop, rollback, or forward-fix plan; preserve evidence and update progress/gates before any retry.

### Do Not

Do not claim Production live when deployment or cutover is deferred.

### Output

PHASE-08 checkpoint and auditable handoff.

### Human Gate

No new gate; report HG-002–HG-005 outcomes.

### Commit

`chore(checkpoint): finalize production readiness` — Task P8-T008.

### Next

Ongoing operations under approved runbooks; no unplanned scope.
