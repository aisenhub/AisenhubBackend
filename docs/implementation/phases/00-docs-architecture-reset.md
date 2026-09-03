# R0 — Documentation and Architecture Reset

Goal: Clean the documentation authority, archive only historically useful design/plan context, remove process-record clutter, and make the breaking-rebuild assumptions impossible to misread before runtime changes begin.

Every task is architecture-authoritative and intentionally breaking where specified. Execution evidence belongs in Git/CI, not in new process Markdown files.

---

## R0-T001 — Verify current repository and docs snapshot

**Dependencies:** None  
**Type:** Read-only discovery

### Goal

Verify current repository and docs snapshot.

### Implementation Steps

1. Confirm `main` HEAD matches or supersedes the documented snapshot.
2. List active docs, archive tree, implementation placeholders, root/scoped AGENTS, package scripts and auth/session files.
3. Record any material drift directly by adjusting this plan before runtime work; do not create a progress report.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Repository source of truth is current.
- [ ] No runtime/cloud mutation occurred.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R0-T001` in the commit message.

---

## R0-T002 — Create curated legacy archive and source manifests

**Dependencies:** R0-T001  
**Type:** Documentation archive

### Goal

Create curated legacy archive and source manifests.

### Implementation Steps

1. Preserve concise V1 architecture/plan summaries.
2. Write exact original paths/blob SHAs for V1 architecture, Master Plan and P0–P8 phase/task sources.
3. Create `superseded-v2-migration` archive containing the previous V2 source identifiers and the compatibility-strategy delta.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Old design intent is recoverable.
- [ ] Archive files clearly say they are non-authoritative.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R0-T002` in the commit message.

---

## R0-T003 — Delete process records and obsolete operational docs

**Dependencies:** R0-T002  
**Type:** Documentation deletion

### Goal

Delete process records and obsolete operational docs.

### Implementation Steps

1. Delete all paths listed in `DOCS_CLEANUP_PLAN.md` under process-record removal.
2. Delete current `implementation/PROGRESS.md` and `TASK_LEDGER.md`.
3. Do not replace them with new progress/checkpoint/report files.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Active docs contain no process diary.
- [ ] Deleted records remain recoverable from Git history.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R0-T003` in the commit message.

---

## R0-T004 — Replace the migration-oriented V2 architecture

**Dependencies:** R0-T002  
**Type:** Architecture

### Goal

Replace the migration-oriented V2 architecture.

### Implementation Steps

1. Replace the active V2 file with Breaking Rebuild Edition.
2. Remove compatibility window, `/v2`, user/session backfill, pilot migration and legacy-retirement phases.
3. Make `/v1` the future first stable public API and state that current `/v1` has no compatibility guarantee.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] Only one active architecture exists.
- [ ] Breaking rebuild assumptions are explicit.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R0-T004` in the commit message.

---

## R0-T005 — Install new Master Plan, phases, execution rules and gates

**Dependencies:** R0-T003,R0-T004  
**Type:** Planning

### Goal

Install new Master Plan, phases, execution rules and gates.

### Implementation Steps

1. Replace current implementation placeholders with this R0–R5 plan.
2. Install Agent Execution Rules and Human Gates.
3. Ensure task dependencies are acyclic and every phase ends in a quality gate.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] All active tasks point only to new architecture.
- [ ] No legacy P0–P8 task is executable from active docs.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R0-T005` in the commit message.

---

## R0-T006 — Update root and scoped AGENTS architecture language

**Dependencies:** R0-T004,R0-T005  
**Type:** Repository governance

### Goal

Update root and scoped AGENTS architecture language.

### Implementation Steps

1. Update root AGENTS authority and platform positioning.
2. Remove general Platform Session/shared-subdomain assumptions.
3. State that existing code/tests are subordinate to Breaking Rebuild architecture.
4. Review `apps/AGENTS.md` / `apps/admin/AGENTS.md` for conflicting auth/session text and update only conflicts.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] No AGENTS file instructs old auth architecture.
- [ ] Admin UI framework/security boundaries remain intact.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R0-T006` in the commit message.

---

## R0-T007 — Strengthen docs and architecture boundary checks

**Dependencies:** R0-T003,R0-T006  
**Type:** Tooling

### Goal

Strengthen docs and architecture boundary checks.

### Implementation Steps

1. Update `scripts/check-docs.mjs` to enforce the new docs policy.
2. Extend boundary checker to detect new shared-parent-cookie SSO, Origin-only authenticated app identity and direct product use of Supabase Platform data.
3. Add negative fixtures for each rule.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] `pnpm docs:check` catches obsolete doc patterns.
- [ ] Boundary negative tests prove new rules.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R0-T007` in the commit message.

---

## R0-T008 — R0 quality gate

**Dependencies:** R0-T005,R0-T006,R0-T007  
**Type:** Quality gate

### Goal

R0 quality gate.

### Implementation Steps

1. Run docs check, format, lint, typecheck, unit tests, build, boundary and secret checks.
2. Verify no database/runtime auth change was made in R0.
3. Commit the documentation reset before starting R1.

### Tests / Proof

- Run the narrowest affected tests first.
- Run every affected DB/RLS/contract/integration/UI/security suite.
- Phase quality-gate tasks run the full applicable repository gate.

### Acceptance Criteria

- [ ] All applicable checks pass.
- [ ] R1 starts from one unambiguous architecture authority.

### Do Not

- Do not preserve obsolete behavior merely to keep an old test green.
- Do not create compatibility shims unless the active architecture explicitly requires one.
- Do not create new process-report/checkpoint/progress documents.
- Do not mutate Production without the applicable Human Gate.

### Commit Convention

Include `R0-T008` in the commit message.
