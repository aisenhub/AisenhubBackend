# R3 — Account, Admin and Business-domain Integration

Goal: Connect the new identity context to Account Center, Admin and all existing business domains, then prove two independent applications work against one user platform.

Every task is architecture-authoritative and intentionally breaking where specified. Execution evidence belongs in Git/CI, not in new process Markdown files.

---

## R3-T001 — Rebuild Account Center login/authorization/consent

**Dependencies:** R2-T008  
**Type:** Account UI

### Goal

Rebuild Account Center login/authorization/consent.

### Implementation Steps

1. Use Supabase OAuth authorization path as protocol authority.
2. Preserve authorization request through login.
3. Render client/scopes and approve/deny through provider adapter.
4. Prevent open redirects.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Authorization Code + PKCE browser journey works.
- [ ] Account UI does not issue codes itself.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R3-T001` in the commit message.

---

## R3-T002 — Add My Applications and app-level account deletion

**Dependencies:** R1-T003,R3-T001  
**Type:** Account domain/UI

### Goal

Add My Applications and app-level account deletion.

### Implementation Steps

1. List actual Memberships only.
2. Support app-level leave/delete without deleting Global Identity.
3. Keep global deletion as a separate operation.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Leaving App A leaves App B usable.
- [ ] Unjoined apps are not presented as user accounts.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R3-T002` in the commit message.

---

## R3-T003 — Move Admin authentication onto the new identity context

**Dependencies:** R2-T008  
**Type:** Admin auth

### Goal

Move Admin authentication onto the new identity context.

### Implementation Steps

1. Treat Admin frontend as a first-party OAuth client.
2. Require active Global Identity + client/application context + `admin_members`.
3. Preserve existing server-side RBAC/MFA/reason/idempotency rules.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Old Admin Platform Session dependency is removed.
- [ ] Normal application membership never grants Admin access.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R3-T003` in the commit message.

---

## R3-T004 — Add Admin Membership and OAuth Client operations

**Dependencies:** R1-T007,R3-T003  
**Type:** Admin API/UI

### Goal

Add Admin Membership and OAuth Client operations.

### Implementation Steps

1. Add Application member list/detail and named suspend/restore/create commands.
2. Expose safe OAuth client binding metadata, not secrets.
3. Use admin-client only; no Supabase Data Provider.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Role matrix is enforced server-side.
- [ ] All risky commands are audited.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R3-T004` in the commit message.

---

## R3-T005 — Scope Entitlement/Catalog access by resolved Application

**Dependencies:** R2-T004  
**Type:** Domain integration

### Goal

Scope Entitlement/Catalog access by resolved Application.

### Implementation Steps

1. Make app-scoped access resolution use server Application Context.
2. Enforce Product/Feature/Application ownership.
3. Keep explicit platform-scope/global features only where intended.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Cross-app entitlement leakage tests fail closed.
- [ ] Existing grant/revoke/restore semantics pass.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R3-T005` in the commit message.

---

## R3-T006 — Scope Redemption/Commerce by resolved Application

**Dependencies:** R2-T004,R3-T005  
**Type:** Domain integration

### Goal

Scope Redemption/Commerce by resolved Application.

### Implementation Steps

1. Attach application context without changing atomic redemption/payment state machines.
2. Reject cross-app ProductVersion/Order/Grant combinations.
3. Preserve concurrency/idempotency/rollback behavior.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Redemption concurrency still has one winner.
- [ ] Refund/chargeback regression tests pass.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R3-T006` in the commit message.

---

## R3-T007 — Scope Feedback/Audit and evolve deletion worker

**Dependencies:** R2-T004,R3-T002  
**Type:** Domain integration

### Goal

Scope Feedback/Audit and evolve deletion worker.

### Implementation Steps

1. Persist explicit application context for authenticated feedback/audit events.
2. Add application-level cleanup workflow.
3. Make global deletion orchestrate all Membership/application cleanup before identity deletion.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Audit can filter app events without string inference.
- [ ] Global/app deletion are not confused.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R3-T007` in the commit message.

---

## R3-T008 — Cross-domain end-to-end quality gate

**Dependencies:** R3-T001,R3-T003,R3-T004,R3-T005,R3-T006,R3-T007  
**Type:** Quality gate

### Goal

Cross-domain end-to-end quality gate.

### Implementation Steps

1. Create two independent web origins/clients and overlapping users.
2. Run login/consent/callback/app-session-or-bearer/API/entitlement/logout journeys.
3. Prove one app login/session does not create the other app session.
4. Run Admin and business-domain regression E2E.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Two unrelated domains work against the same identity backend.
- [ ] No shared Cookie dependency exists.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R3-T008` in the commit message.
