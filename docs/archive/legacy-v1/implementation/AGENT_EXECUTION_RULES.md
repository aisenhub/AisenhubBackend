# AisenHub Platform Agent Execution Rules

> Mandatory reading before every implementation task.

## 1. Authority order

1. `docs/AISENHUB_PLATFORM_BACKEND_ARCHITECTURE.md` — sole architecture authority.
2. Approved ADRs, including `docs/admin架构.md`.
3. `docs/implementation/MASTER_PLAN.md`.
4. Current Phase / Atomic Task.
5. Repository root `AGENTS.md`.
6. The nearest directory-scoped `AGENTS.md` (the current `app/AGENTS.md` declares the future `apps/admin/` scope and must be preserved when that directory is scaffolded).
7. Existing implementation and tests.
8. Agent judgment.

Do not redesign the data model, API boundary, Auth/session model, entitlement semantics, Query/Command split, Admin security boundary, Refine choice, or the initial Supabase/PostgreSQL/RLS/Edge Functions route. If implementation cannot safely continue without changing architecture, stop only the affected task and create `docs/implementation/blockers/AB-NNN.md` with `ARCHITECTURE_BLOCKER` status.

## 2. Execution states

- `AUTONOMOUS`: default. Inspect, implement, run tests, debug, fix, and continue without asking the user.
- `HUMAN_GATE`: allowed only for external authorization, unavailable secrets, unavailable external resources, real DNS, product/commercial decisions, or production-risk actions.
- `BLOCKED`: only after safe local alternatives and multiple repair attempts are exhausted, or an architecture blocker is documented.

Never turn an ordinary technical choice, test failure, missing local fixture, package installation, Docker startup, local certificate, or browser automation into a Human Gate.

## 3. Task lifecycle

```text
pending → in_progress → implement → test → repair → retest → completed
                               ↘ documented blocker / human gate only when allowed
```

Before work:

1. Read this file, repository root `AGENTS.md`, the nearest applicable directory `AGENTS.md`, the current task, and its cited architecture sections.
2. Confirm dependencies are completed in `TASK_LEDGER.md`.
3. Update task status and `PROGRESS.md` to `in_progress`.
4. Inspect existing files and preserve unrelated user changes.

After work:

1. Run every task test and acceptance command.
2. Repair failures and rerun until all applicable checks pass.
3. Update task status only from actual command results.
4. Commit at the declared boundary.
5. Record Task ID, result, tests, and commit SHA in `TASK_LEDGER.md` and `PROGRESS.md`.
6. Continue to the declared next ready task unless the user explicitly says stop/hold.

## 4. Autonomous-first rules

The Agent may autonomously inspect code/docs, install declared development dependencies, create local configuration, run Docker and Supabase Local, reset/seed local databases, create test users, generate local certificates, run Playwright, and modify code/tests within the current task.

When several implementation choices satisfy the architecture, choose in this order:

```text
architecture consistency
→ existing repository convention
→ testability
→ minimum complexity
→ smallest dependency surface
```

Do not ask “which approach do you prefer?” for a reversible technical detail that tests can settle.

## 5. Human Gate rules

Allowed categories are H1 external account auth, H2 secret/credential, H3 external resource creation without available permission, H4 real DNS, H5 commercial Product Decision, and H6 production risk.

Before raising a gate:

- verify current CLI/session/environment first;
- finish every independent Local task;
- batch all missing user actions for the stage into one request;
- update `HUMAN_GATES.md` to `ready` or `waiting` with evidence;
- update `PROGRESS.md` without pausing unrelated work.

Never ask the user to paste secrets into chat or source. Direct them to the named secret manager/environment and verify presence without printing values.

## 6. Local, Staging, Production

- Local: zero-human target. Use Docker, Supabase Local, fixtures, mocks, and Playwright.
- Staging: enter only after the Local quality gates pass. Trigger at most one consolidated gate if authorization/resources are unavailable.
- Production: never mutate production before explicit approval. Before the gate, prepare migration, deploy, smoke, recovery, and rollback plans only.

Production destructive operations, real payment cutover, production DNS, large entitlement changes, and production secret changes always require explicit authorization.

## 7. Test-before-next-task

For RLS, Redemption, Entitlement, Session, CSRF, CORS, Idempotency, Refund, and Admin Permission, write or establish failing tests before implementation when practical. A task is not complete because code exists; all acceptance checks must pass.

Do not claim PASS unless the command was executed successfully. Do not hide skipped or failing tests. Do not use “should work” as evidence.

## 8. Quality gates

Every phase runs all applicable checks:

```text
format check
lint
typecheck
unit tests
database tests
RLS tests
API contract tests
integration tests
Edge Function tests
Playwright E2E
Supabase local reset
build
secret/dependency-boundary scan
```

An inapplicable check must be recorded as `N/A` with a reason, never silently omitted.

## 9. Architecture and security prohibitions

- No silent architecture drift or scope expansion.
- No Admin direct PostgreSQL/Data API access or Refine Supabase Data Provider.
- No Service Role Key, API secret, token, password, redemption plaintext, or payment secret in code, logs, fixtures committed to Git, browser storage, or generated artifacts.
- No second Auth, second RBAC authority, client-authoritative Audit, generic status mutation, SQL builder, low-code/workflow engine, OpenFGA, Kafka, Redis, microservices, Kubernetes, Event Sourcing, or CQRS infrastructure.
- No dependency substitution without a documented, architecture-compatible reason.
- No TODO/stub replacing required functionality at task completion.
- No destructive production operation or production migration without a Human Gate.

## 10. Git and concurrency

- One atomic task or tightly coupled task group per clear commit.
- Commit format: `type(scope): summary`, and include Task ID in the body or footer.
- Do not bundle unrelated formatting or refactors.
- Respect `Parallel Safe`; parallel agents must not edit the same migration, contract, lockfile, shared provider, or progress file concurrently.
- Phase gate completion creates a checkpoint document and checkpoint commit/tag as repository policy allows.

## 11. Failure recovery

On failure: read the complete error, isolate the smallest cause, inspect relevant docs/code, repair, and rerun the narrow check followed by the task gate. Try multiple safe repair cycles. Revert only the current task's isolated changes when necessary; never discard unrelated work.

Escalate only when credentials/permissions are unavailable, a commercial decision is required, production risk is reached, or architecture is contradictory. An architecture blocker file must contain current rule, evidence, why safe implementation cannot proceed, minimum proposal, affected tasks, workaround, and status.

## 12. Progress truthfulness

Maintain the five-level trace:

```text
Architecture → MASTER_PLAN → Phase → Atomic Task → Commit + Tests
```

Update `PROGRESS.md`, `TASK_LEDGER.md`, Human Gates, blockers, and phase checkpoints at the times defined by this plan. Preserve important historical failures, gates, and blockers; record decisions/results, not low-value debug chatter.

## 13. Repository-specific Admin UI rules

The current repository rules fix Admin implementation to React + Vite + Refine Core + `@refinedev/antd` + Ant Design. Ant Design is the sole primary component system. `packages/design-system` supplies theme tokens, status semantics, interaction conventions, and genuinely reusable domain components; it must not reimplement Ant Button, Table, Form, Modal, Drawer, or DatePicker.

Before Admin work, read root `AGENTS.md` and the Admin-scoped rules currently stored at `app/AGENTS.md` (expected final location: `apps/admin/AGENTS.md`). Do not introduce shadcn/ui, Material UI, a second component framework, or Tailwind as a parallel component system.
