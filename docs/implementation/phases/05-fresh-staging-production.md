# R5 — Fresh Staging and Production Release

Goal: Deploy the clean baseline as a fresh platform, prove OAuth across independent domains, then perform an explicitly approved Production deployment without carrying legacy migration machinery.

Every task is architecture-authoritative and intentionally breaking where specified. Execution evidence belongs in Git/CI, not in new process Markdown files.

---

## R5-T001 — Fresh-rebuild Staging from clean baseline

**Dependencies:** R4-T007  
**Type:** Staging deploy

### Goal

Fresh-rebuild Staging from clean baseline.

### Implementation Steps

1. Verify target is Staging.
2. Use existing access or HG-001 only when unavailable.
3. Reset/recreate Staging database as allowed by the no-user assumption.
4. Deploy baseline migrations, functions, Account/Admin and register separate Staging OAuth clients/redirects.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Staging migration history equals clean baseline.
- [ ] No Production resource is touched.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R5-T001` in the commit message.

---

## R5-T002 — Run full Staging OAuth/domain/business verification

**Dependencies:** R5-T001  
**Type:** Staging quality

### Goal

Run full Staging OAuth/domain/business verification.

### Implementation Steps

1. Run two-domain OAuth Authorization Code + PKCE E2E.
2. Verify JWKS/signing, Membership isolation, Origin secondary check, Admin RBAC, Entitlement, Redemption, Commerce, deletion, observability and recovery.
3. Run provider-config drift checks where supported.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] All Staging release journeys pass.
- [ ] No shared Cookie/custom-domain dependency exists.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R5-T002` in the commit message.

---

## R5-T003 — Prepare Production fresh-deploy dossier and obtain HG-002

**Dependencies:** R5-T002  
**Type:** Production gate

### Goal

Prepare Production fresh-deploy dossier and obtain HG-002.

### Implementation Steps

1. Inspect Production read-only.
2. Pin Git SHA/artifacts/baseline migrations/OAuth clients/environment variables.
3. Describe destructive reset/replacement, backup decision, smoke, stop and recovery plan.
4. Obtain explicit HG-002 approval before mutation.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Production target/scope is explicit.
- [ ] Approval covers exact destructive actions.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R5-T003` in the commit message.

---

## R5-T004 — Deploy Production and run immediate smoke

**Dependencies:** R5-T003  
**Type:** Production deploy

### Goal

Deploy Production and run immediate smoke.

### Implementation Steps

1. Reconfirm target identity and approved artifact SHA.
2. Apply clean baseline/fresh deployment exactly as approved.
3. Configure Production OAuth clients with exact HTTPS redirects.
4. Run identity/app/admin/public/webhook smoke and stop on defined conditions.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Production matches approved architecture.
- [ ] No legacy auth compatibility component is deployed.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R5-T004` in the commit message.

---

## R5-T005 — Final repository/docs cleanup and release gate

**Dependencies:** R5-T004  
**Type:** Final quality gate

### Goal

Final repository/docs cleanup and release gate.

### Implementation Steps

1. Search repo/docs for obsolete `/v2` migration language, Platform Cookie SSO, Origin-auth authority and process-record docs.
2. Run final platform/security/E2E/build/docs checks.
3. Keep the plan and architecture; do not create a completion report/checkpoint.
4. Use Git commit/release tag/CI as completion evidence.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Only the breaking-rebuild architecture remains active.
- [ ] Docs are compact and non-contradictory.
- [ ] Repository is ready for future independent products.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R5-T005` in the commit message.
