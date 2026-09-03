# R1 — Identity, Membership and OAuth Client Foundation

Goal: Rebuild the data model around Global Identity + Application Membership + OAuth Client Binding, with no legacy user/session migration.

Every task is architecture-authoritative and intentionally breaking where specified. Execution evidence belongs in Git/CI, not in new process Markdown files.

---

## R1-T001 — Write target identity/membership/client invariants test-first

**Dependencies:** R0-T008  
**Type:** Database specification

### Goal

Write target identity/membership/client invariants test-first.

### Implementation Steps

1. Add pgTAP/RLS expectations for Global Profile, Application, Membership and OAuth Client Binding.
2. Prove Global Identity alone does not grant Application access.
3. Specify unique app/user Membership and unique external client binding.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Tests express every core identity invariant.
- [ ] They fail only on missing/new implementation.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R1-T001` in the commit message.

---

## R1-T002 — Extend Application Registry for registration and membership policy

**Dependencies:** R1-T001  
**Type:** Database schema

### Goal

Extend Application Registry for registration and membership policy.

### Implementation Steps

1. Add minimal registration/membership policy fields to `platform_apps`.
2. Keep slug/application identity immutability.
3. Keep arbitrary-domain support through exact origins.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Policy constraints pass.
- [ ] No `*.aisenhub.com` assumption exists.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R1-T002` in the commit message.

---

## R1-T003 — Create Application Membership schema and lifecycle commands

**Dependencies:** R1-T001,R1-T002  
**Type:** Database domain

### Goal

Create Application Membership schema and lifecycle commands.

### Implementation Steps

1. Create private `application_memberships`.
2. Implement create/activate/suspend/restore/leave/delete transitions with audit/idempotency where required.
3. Never mutate Global Profile status as a side effect of app-level lifecycle.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Illegal transitions rollback.
- [ ] Cross-application membership isolation tests pass.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R1-T003` in the commit message.

---

## R1-T004 — Create OAuth Client Binding schema

**Dependencies:** R1-T002  
**Type:** Database domain

### Goal

Create OAuth Client Binding schema.

### Implementation Steps

1. Create private `application_oauth_clients`.
2. Bind each provider external `client_id` to exactly one Application.
3. Add public/confidential, environment and active/disabled constraints.
4. Do not add a duplicate redirect-URI table in first release.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Client binding is deterministic and private.
- [ ] Production/dev client identities cannot be confused.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R1-T004` in the commit message.

---

## R1-T005 — Remove Platform Session from target database model

**Dependencies:** R1-T001  
**Type:** Breaking schema cleanup

### Goal

Remove Platform Session from target database model.

### Implementation Steps

1. Identify tables/functions/views/RPCs whose only purpose is shared Platform Cookie Session/CSRF exchange.
2. Create breaking migrations that remove or detach them from new runtime.
3. Keep Admin membership but not legacy session coupling.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] New target schema has no universal product Platform Session dependency.
- [ ] No new Membership code reads legacy session state.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R1-T005` in the commit message.

---

## R1-T006 — Replace identity/application fixtures instead of backfilling

**Dependencies:** R1-T003,R1-T004,R1-T005  
**Type:** Fixtures

### Goal

Replace identity/application fixtures instead of backfilling.

### Implementation Steps

1. Delete legacy fixture assumptions tied to old sessions/users.
2. Create deterministic Global Identities, multiple Applications, overlapping/non-overlapping Memberships and dev OAuth client bindings.
3. Do not infer Memberships from historical tables.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] `db:reset` creates the new model deterministically.
- [ ] Fixture verification proves app isolation.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R1-T006` in the commit message.

---

## R1-T007 — Add Membership/OAuth contracts and backend projections

**Dependencies:** R1-T003,R1-T004  
**Type:** Contracts/API primitives

### Goal

Add Membership/OAuth contracts and backend projections.

### Implementation Steps

1. Add runtime schemas and stable errors.
2. Add My Applications, App Membership and Admin member/client projections.
3. Keep provider secrets/internal OAuth records out of contracts.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Contract tests pass.
- [ ] Private DB shape is not exposed.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R1-T007` in the commit message.

---

## R1-T008 — R1 quality gate

**Dependencies:** R1-T006,R1-T007  
**Type:** Quality gate

### Goal

R1 quality gate.

### Implementation Steps

1. Run clean reset twice, type generation, DB/RLS/contract/integration/unit/boundary/secret checks.
2. Confirm no backfill/compatibility code exists.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] All applicable checks pass.
- [ ] Data model is ready for OAuth auth kernel.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R1-T008` in the commit message.
