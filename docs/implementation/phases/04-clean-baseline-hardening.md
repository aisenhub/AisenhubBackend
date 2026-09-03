# R4 — Clean Baseline, Dead-code Removal and Security Hardening

Goal: After behavior is correct, remove historical implementation baggage, modularize shared code, squash migrations and make a clean-from-zero rebuild the only supported development baseline.

Every task is architecture-authoritative and intentionally breaking where specified. Execution evidence belongs in Git/CI, not in new process Markdown files.

---

## R4-T001 — Modularize shared Platform/Admin Edge code

**Dependencies:** R3-T008  
**Type:** Maintainability refactor

### Goal

Modularize shared Platform/Admin Edge code.

### Implementation Steps

1. Split HTTP, auth, DB gateway, domain and router responsibilities.
2. Move service-role access behind privileged DB gateway.
3. Keep external API behavior fixed to the new architecture.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] No circular dependency introduced.
- [ ] Entrypoints remain thin.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R4-T001` in the commit message.

---

## R4-T002 — Delete all dead legacy auth/session code and tests

**Dependencies:** R4-T001  
**Type:** Code cleanup

### Goal

Delete all dead legacy auth/session code and tests.

### Implementation Steps

1. Search for old Platform Session cookie/CSRF/session-exchange helpers and routes.
2. Delete obsolete contracts, fixtures and compatibility tests.
3. Delete any package/module that exists only for legacy auth.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Repository search finds no unsupported shared-session path.
- [ ] All remaining tests describe target architecture.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R4-T002` in the commit message.

---

## R4-T003 — Freeze final database schema and generate clean baseline migration series

**Dependencies:** R4-T002  
**Type:** Migration squash

### Goal

Freeze final database schema and generate clean baseline migration series.

### Implementation Steps

1. Verify final schema/functions/grants from current working migrations.
2. Create small ordered baseline migration series by stable domain.
3. Delete old historical migration chain after baseline parity is proven.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Empty DB rebuild matches target schema.
- [ ] No obsolete session table/function exists in baseline.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R4-T003` in the commit message.

---

## R4-T004 — Regenerate fixtures/types and prove two clean rebuilds

**Dependencies:** R4-T003  
**Type:** Determinism

### Goal

Regenerate fixtures/types and prove two clean rebuilds.

### Implementation Steps

1. Regenerate Supabase types.
2. Rewrite seeds/fixtures against baseline only.
3. Run consecutive full resets and compare generated-type hash/schema expectations.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Two clean rebuilds pass identically.
- [ ] No migration history dependency exists.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R4-T004` in the commit message.

---

## R4-T005 — Upgrade architecture/boundary/CI enforcement

**Dependencies:** R4-T002,R4-T004  
**Type:** CI/security tooling

### Goal

Upgrade architecture/boundary/CI enforcement.

### Implementation Steps

1. Make `platform:verify` operate on clean baseline.
2. Run real OAuth Playwright smoke on PR rather than discovery only.
3. Add privileged-function invariant scan and V2 boundary negative tests.
4. Pin mutable GitHub Actions references to commit SHAs where practical.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] CI fails on legacy auth regression.
- [ ] PR gate executes real browser auth smoke.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R4-T005` in the commit message.

---

## R4-T006 — Run full security and data-isolation audit

**Dependencies:** R4-T004,R4-T005  
**Type:** Security audit

### Goal

Run full security and data-isolation audit.

### Implementation Steps

1. Audit JWT validation, OAuth redirect/state/PKCE, client mapping, membership isolation, CORS, secrets, SQL grants/search_path, Admin bundle, deletion, Commerce and Audit.
2. Fix all high-confidence findings before gate.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] No unresolved high-severity finding remains.
- [ ] Secret scan and cross-app leakage tests pass.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R4-T006` in the commit message.

---

## R4-T007 — R4 clean-rebuild release-candidate gate

**Dependencies:** R4-T001,R4-T006  
**Type:** Quality gate

### Goal

R4 clean-rebuild release-candidate gate.

### Implementation Steps

1. Run `platform:verify`, full E2E release journey, redemption concurrency, security, docs, boundaries and secret checks from clean checkout/reset assumptions.
2. Verify active docs match final code.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Local release candidate is fully reproducible.
- [ ] R5 can deploy without legacy migration steps.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R4-T007` in the commit message.
