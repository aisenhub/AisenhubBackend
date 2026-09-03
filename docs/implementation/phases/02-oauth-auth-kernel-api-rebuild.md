# R2 — OAuth, Auth Kernel and API Breaking Rebuild

Goal: Replace shared Cookie Session authentication with OAuth/OIDC token-derived Application Context and make the clean `/v1` API use the new semantics directly.

Every task is architecture-authoritative and intentionally breaking where specified. Execution evidence belongs in Git/CI, not in new process Markdown files.

---

## R2-T001 — Verify and configure current Supabase OAuth/OIDC capability

**Dependencies:** R1-T008  
**Type:** Provider foundation

### Goal

Verify and configure current Supabase OAuth/OIDC capability.

### Implementation Steps

1. Re-read official Supabase OAuth Server docs at execution time.
2. Verify local/cloud support for Authorization Code + PKCE, refresh, OIDC/JWKS, `client_id`, public/confidential clients and exact redirects.
3. Verify asymmetric signing/JWKS path; use HG-001 only if external authorization is missing.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Provider assumptions are current.
- [ ] No secret is committed or echoed.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R2-T001` in the commit message.

---

## R2-T002 — Implement provider adapter and Account authorization protocol boundary

**Dependencies:** R2-T001  
**Type:** Provider adapter

### Goal

Implement provider adapter and Account authorization protocol boundary.

### Implementation Steps

1. Create a small provider interface around authorization details, approve/deny and token/discovery endpoints.
2. Keep Supabase-specific URLs/SDK calls inside auth adapter modules.
3. Do not implement authorization-code/refresh-token storage in Platform DB.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Provider can be mocked in tests.
- [ ] Business modules do not depend on Supabase OAuth internals.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R2-T002` in the commit message.

---

## R2-T003 — Implement JWKS access-token verifier

**Dependencies:** R2-T001  
**Type:** Security kernel

### Goal

Implement JWKS access-token verifier.

### Implementation Steps

1. Verify signature, issuer, expiry and token expectations before trusting claims.
2. Normalize only verified claims needed by Platform.
3. Never log raw access/refresh tokens.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Invalid signature/issuer/expiry fails closed.
- [ ] Key rotation fixtures are covered.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R2-T003` in the commit message.

---

## R2-T004 — Implement authenticated Application Context kernel

**Dependencies:** R1-T003,R1-T004,R2-T003  
**Type:** Security kernel

### Goal

Implement authenticated Application Context kernel.

### Implementation Steps

1. Resolve verified `client_id` -> OAuth binding -> Application.
2. Verify Profile/Application/Client/Membership active state.
3. Return one normalized context for all handlers.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] App A identity cannot select App B via request input.
- [ ] Suspended/absent membership denies access.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R2-T004` in the commit message.

---

## R2-T005 — Reduce Origin to browser security evidence

**Dependencies:** R2-T004  
**Type:** CORS/browser security

### Goal

Reduce Origin to browser security evidence.

### Implementation Steps

1. Keep exact Origin allow-list.
2. For browser auth requests require Origin to belong to token-derived Application.
3. Allow non-browser clients with no Origin.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Wrong Origin + valid token is denied.
- [ ] Desktop-style no-Origin request works.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R2-T005` in the commit message.

---

## R2-T006 — Rewrite `/v1` Account/App API auth and delete legacy session routes

**Dependencies:** R2-T004,R2-T005  
**Type:** Breaking API rewrite

### Goal

Rewrite `/v1` Account/App API auth and delete legacy session routes.

### Implementation Steps

1. Create final `/v1/account/*` and `/v1/app/*` route semantics.
2. Remove session exchange, universal Platform Cookie, legacy CSRF-session dependencies and old `/v1/session` behavior.
3. Delete obsolete contracts/handlers/tests instead of keeping compatibility aliases.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] No authenticated app route depends on legacy Platform Session.
- [ ] RequestId/error envelope remains stable.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R2-T006` in the commit message.

---

## R2-T007 — Rebuild platform-client and add auth-client

**Dependencies:** R2-T002,R2-T006  
**Type:** SDK

### Goal

Rebuild platform-client and add auth-client.

### Implementation Steps

1. Make platform-client Bearer/Application-context first.
2. Create OAuth PKCE/state/nonce/callback helpers in auth-client.
3. Keep confidential secrets server-only.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] SDK has no DB knowledge.
- [ ] Old cookie transport code is removed when no longer used.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R2-T007` in the commit message.

---

## R2-T008 — R2 security matrix and quality gate

**Dependencies:** R2-T006,R2-T007  
**Type:** Quality gate

### Goal

R2 security matrix and quality gate.

### Implementation Steps

1. Test same user/two apps, same app/multiple clients, missing/suspended membership, disabled app/client, wrong Origin, no-Origin native client, invalid JWT.
2. Run DB/RLS/contract/integration/functions/unit/E2E/build/boundary/secret/security checks.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] All new auth paths fail closed.
- [ ] No legacy auth fallback remains.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R2-T008` in the commit message.
