# Phase P0 — Autonomous Bootstrap

Goal: establish a deterministic, zero-human Local foundation. Human Interaction Budget: **0**.

## P0-T001 — Inventory prerequisites and record environment baseline

Status: pending  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: discovery  
Track: G — DevOps  
Parallel Safe: no

### Architecture References

- Main architecture §6 Code and repository boundaries
- §18 Environment and release
- §19 Platform Phase 0

### Dependencies

None.

### Goal

Inspect the empty/document-only repository and local toolchain, then record reproducible choices without implementing business behavior.

### Inputs

Repository, architecture docs, root `AGENTS.md`, Admin-scoped `app/AGENTS.md`, installed Node/pnpm/Docker/Supabase CLI/Git.

### Files To Inspect

`docs/*.md`, repository root, root `AGENTS.md`, `app/AGENTS.md`, global/local tool versions.

### Files To Create

`docs/implementation/ENVIRONMENT_BASELINE.md`, `.tool-versions` or equivalent pinned-version file.

### Files To Modify

`PROGRESS.md`, `TASK_LEDGER.md`.

### Implementation Steps

1. Confirm repository contents, both existing AGENTS rule files, and whether Git is initialized.
2. Detect Node, pnpm, Docker, Supabase CLI, Git, and browser-test prerequisites.
3. Select supported pinned versions from current stable compatible releases and official requirements.
4. Record present/missing tools and automatic install commands; install missing local development tools when safe.
5. Do not request cloud accounts.

### Commands

```bash
node --version
pnpm --version
docker version
supabase --version
git status
```

### Tests

Parse each version command; verify Docker daemon can answer or document an autonomous startup/install remediation.

### Acceptance Criteria

- [ ] Environment baseline lists exact versions and repository state.
- [ ] Every missing Local prerequisite has been installed or has an executable autonomous remediation.
- [ ] No cloud credential is required.
- [ ] Progress and ledger identify P0-T002 as next.

### Failure Recovery

Retry detection with platform-native paths/package manager; start Docker automatically where possible. A locked-down machine permission is a blocker only after local alternatives fail.

### Do Not

Do not create cloud projects, business tables, or choose a different architecture stack.

### Output

Verified environment baseline.

### Human Gate

None; Local prerequisite setup is autonomous.

### Commit

`docs(bootstrap): record local environment baseline` — Task P0-T001.

### Next

P0-T002.

## P0-T002 — Create pnpm workspace and root tooling

Status: pending  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: foundation  
Track: G — DevOps  
Parallel Safe: no

### Architecture References

- Main architecture §6.1 repository structure
- §18.2 database baseline

### Dependencies

P0-T001.

### Goal

Create the monorepo workspace, pinned package manager, TypeScript, formatting, linting, testing, and build conventions.

### Inputs

Environment baseline and repository structure from architecture.

### Files To Inspect

Root files and `ENVIRONMENT_BASELINE.md`.

### Files To Create

`package.json`, `pnpm-workspace.yaml`, `tsconfig.base.json`, formatter/linter/test configs, `.editorconfig`, `.gitignore`, `.env.example`.

### Files To Modify

Progress and ledger.

### Implementation Steps

1. Initialize pnpm workspace for `apps/*` and `packages/*`.
2. Add pinned TypeScript, formatter, linter, unit-test, and workspace orchestration dependencies.
3. Define root scripts: format/check, lint, typecheck, test, build, and clean-safe.
4. Ensure `.env*` secrets are ignored while `.env.example` is tracked.

### Commands

```bash
pnpm install
pnpm format:check
pnpm lint
pnpm typecheck
```

### Tests

Run root tooling against the current workspace and verify empty-workspace success is not implemented with ignored failures.

### Acceptance Criteria

- [ ] `pnpm install --frozen-lockfile` succeeds after lockfile creation.
- [ ] Format, lint, and typecheck scripts exit 0.
- [ ] Package manager and runtime versions are pinned.
- [ ] Secret-bearing env files are ignored.

### Failure Recovery

Resolve config/package compatibility using official docs and smallest supported configuration; do not swap the chosen stack.

### Do Not

Do not add framework-specific business dependencies or suppress errors with `|| true`.

### Output

Reproducible root workspace tooling.

### Human Gate

None.

### Commit

`chore(repo): initialize pnpm workspace tooling` — Task P0-T002.

### Next

P0-T003.

## P0-T003 — Scaffold approved apps and packages

Status: pending  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: foundation  
Track: C/D/E/G  
Parallel Safe: no

### Architecture References

- Main architecture §6.1 repository structure and package dependency direction
- §15.1 Admin technical boundary

### Dependencies

P0-T002.

### Goal

Create compileable skeletons for account/admin and all approved shared packages with enforced one-way dependencies, while preserving the repository's existing AGENTS rules.

### Inputs

Workspace config and architecture package responsibilities.

### Files To Inspect

Root package/workspace/TypeScript configs, root `AGENTS.md`, and `app/AGENTS.md`.

### Files To Create

`apps/account`, `apps/admin`, `packages/platform-client`, `packages/admin-client`, `packages/contracts`, `packages/design-system`, `packages/config` package manifests and minimal source/test entrypoints; final Admin-scoped `apps/admin/AGENTS.md` preserved from the existing `app/AGENTS.md`.

### Files To Modify

Workspace config, root scripts, progress, ledger.

### Implementation Steps

1. Scaffold minimal React apps without product behavior; Admin uses Vite, Refine, `@refinedev/antd`, and Ant Design as required by repository rules.
2. Scaffold package entrypoints and explicit exports.
3. Add dependency-boundary lint rules: apps may depend on packages; clients depend on contracts; design-system cannot depend on clients; clients cannot depend on each other.
4. Preserve the content/history of `app/AGENTS.md` at its declared `apps/admin/AGENTS.md` scope; do not silently discard or overwrite either ruleset.
5. Add a boundary test that fails on Supabase imports in `admin-client` and a UI dependency check that rejects a second primary Admin component framework.

### Commands

```bash
pnpm install
pnpm -r typecheck
pnpm -r build
pnpm boundaries:check
```

### Tests

Workspace graph test and deliberate forbidden-import fixture/test.

### Acceptance Criteria

- [ ] Every approved app/package builds.
- [ ] No circular dependency exists.
- [ ] `admin-client` has no Supabase/database dependency.
- [ ] Admin uses Refine + Ant Design and its scoped AGENTS rules are present under `apps/admin/`.
- [ ] Boundary checker exits 0 on repository and fails against its negative fixture.

### Failure Recovery

Fix exports/project references and dependency direction; do not merge clients or move Admin code into contracts.

### Do Not

Do not implement auth, data models, CRUD pages, or direct database access.

### Output

Approved monorepo skeleton.

### Human Gate

None.

### Commit

`chore(repo): scaffold platform workspaces` — Task P0-T003.

### Next

P0-T004 and P0-T008 may proceed after merge.

## P0-T004 — Initialize Supabase Local and Edge Function layout

Status: pending  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: infrastructure  
Track: A/B/G  
Parallel Safe: yes

### Architecture References

- Main architecture §6.1 Supabase layout
- §13.1 schema boundary
- §18.1 environments

### Dependencies

P0-T003.

### Goal

Create Local Supabase configuration and approved function directories with no cloud dependency.

### Inputs

Pinned Supabase CLI and architecture function groups.

### Files To Inspect

Workspace and environment baseline.

### Files To Create

`supabase/config.toml`, `supabase/functions/_shared`, `platform-api`, `platform-public`, `platform-admin`, `payment-webhook`, local env examples.

### Files To Modify

Root scripts and docs for Local start/stop/status.

### Implementation Steps

1. Initialize Supabase Local.
2. Configure deterministic ports and non-production defaults.
3. Add minimal health handlers only where required to prove function test infrastructure.
4. Add root scripts for start, stop, status, reset, serve, and type generation.

### Commands

```bash
pnpm supabase:start
pnpm supabase:status
pnpm functions:test
```

### Tests

Start/status and a local function health test; verify no remote project ref is required.

### Acceptance Criteria

- [ ] Local Supabase starts and reports healthy.
- [ ] Four approved function groups and shared folder exist.
- [ ] Function smoke test exits 0.
- [ ] No cloud configuration or real secret is committed.

### Failure Recovery

Repair Docker/port conflicts autonomously and record changed local ports in the baseline.

### Do Not

Do not link a cloud project or create extra services.

### Output

Working Local Supabase/function shell.

### Human Gate

None.

### Commit

`chore(supabase): initialize local platform runtime` — Task P0-T004.

### Next

P0-T005.

## P0-T005 — Create platform schema, role, and idempotency baseline migration

Status: pending  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: database  
Track: A  
Parallel Safe: no

### Architecture References

- Main architecture §8.8 idempotency_records
- §13 schema/security boundary
- §18.2 clean baseline

### Dependencies

P0-T004.

### Goal

Create the clean initial migration foundation: private `platform` schema, least-privilege grants, helper conventions, and unified idempotency table.

### Inputs

Approved idempotency fields/invariants and local Supabase roles.

### Files To Inspect

Supabase config and architecture §§8.8, 13.

### Files To Create

`supabase/migrations/0001_aisenhub_platform_baseline.sql`.

### Files To Modify

Database test manifests and progress files.

### Implementation Steps

1. Create private schema and revoke default anon/authenticated access.
2. Create reusable timestamp/UUID conventions only when architecture-compatible.
3. Create `idempotency_records` with unique scope/actor/key and request-hash checks.
4. Restrict writes to service/database functions.

### Commands

```bash
pnpm db:reset
pnpm db:test
```

### Tests

Schema exposure, grants, idempotency uniqueness, same-key/different-hash rejection, and reset reproducibility.

### Acceptance Criteria

- [ ] Local reset exits 0 from an empty database.
- [ ] `platform` is not exposed to anon/authenticated.
- [ ] Idempotency constraints match architecture.
- [ ] Repeating reset produces the same schema.

### Failure Recovery

Fix migration forward; because there is no production data, recreate Local database rather than layering ad-hoc repair SQL.

### Do Not

Do not create all domain tables prematurely or expose `platform` via Data API.

### Output

Clean database security/idempotency baseline.

### Human Gate

None.

### Commit

`feat(db): add platform schema and idempotency baseline` — Task P0-T005.

### Next

P0-T006.

## P0-T006 — Establish SQL, RLS, function, and API test harnesses

Status: pending  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: testing  
Track: F  
Parallel Safe: yes

### Architecture References

- Main architecture §16 Test strategy
- §13 Data access/security

### Dependencies

P0-T004, P0-T005.

### Goal

Provide reusable automated harnesses for database constraints, RLS allow/deny, Edge Functions, contracts, integration, and Playwright.

### Inputs

Local Supabase endpoints and workspace tooling.

### Files To Inspect

Current test configs and Supabase layout.

### Files To Create

`supabase/tests` helpers/smoke suites, API test helpers, Playwright config/fixtures, function-test config.

### Files To Modify

Root/package scripts.

### Implementation Steps

1. Select minimal supported SQL test mechanism compatible with Supabase Local.
2. Add authenticated/anon/service test contexts.
3. Add HTTP helpers that preserve cookies/CSRF/requestId.
4. Add browser project and deterministic ports.
5. Add a negative test proving failing checks produce nonzero exit status.

### Commands

```bash
pnpm db:test
pnpm rls:test
pnpm functions:test
pnpm test:contract
pnpm test:e2e --list
```

### Tests

Harness self-tests and one intentional-failure fixture per critical runner.

### Acceptance Criteria

- [ ] Every harness can run locally without cloud access.
- [ ] Failing fixtures fail the command.
- [ ] Cookie/CSRF and role fixtures are reusable.
- [ ] Test commands are noninteractive.

### Failure Recovery

Replace only an incompatible test runner, preserving PostgreSQL/Supabase and evidence requirements; document the reason.

### Do Not

Do not weaken tests to make the harness green.

### Output

Reusable automated test foundation.

### Human Gate

None.

### Commit

`test(platform): establish local test harnesses` — Task P0-T006.

### Next

P0-T007.

## P0-T007 — Create deterministic seed and local identities

Status: pending  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: fixtures  
Track: A/F  
Parallel Safe: no

### Architecture References

- Main architecture §18.2 deterministic seed
- §8.7 admin roles
- Implementation requirement: owner/admin/support/finance/normal-user fixtures

### Dependencies

P0-T006.

### Goal

Create deterministic non-secret fixtures and an automated Local Auth user bootstrap for all required roles.

### Inputs

Supabase Local Auth and fixed test identifiers.

### Files To Inspect

Baseline migration, test helpers, `.env.example`.

### Files To Create

`supabase/seed.sql`, local-only Auth fixture script, fixture constants package/module.

### Files To Modify

Reset/test scripts.

### Implementation Steps

1. Define stable UUIDs and test-only emails/passwords clearly marked Local.
2. Create users through supported Local Auth APIs/seed mechanism.
3. Seed only data available at this phase; later phases extend deterministically.
4. Ensure reset can run repeatedly without duplicate failures.

### Commands

```bash
pnpm db:reset
pnpm fixtures:verify
```

### Tests

Verify five identities exist, credentials work only locally, and two resets yield identical fixture identifiers.

### Acceptance Criteria

- [ ] owner/admin/support/finance/normal-user fixtures are reproducible.
- [ ] No production-like secret is committed.
- [ ] Reset plus fixture verification exits 0 twice.

### Failure Recovery

Use supported Local Auth admin APIs instead of direct unsupported auth table writes if seed behavior is unstable.

### Do Not

Do not use real user data or require manual account creation.

### Output

Deterministic Local identity fixtures.

### Human Gate

None.

### Commit

`test(fixtures): add deterministic local identities` — Task P0-T007.

### Next

P0-T008.

## P0-T008 — Define contracts and error-envelope skeleton

Status: pending  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: contracts  
Track: C  
Parallel Safe: yes

### Architecture References

- Main architecture §11.2 Contract rules
- §6 package responsibilities

### Dependencies

P0-T003.

### Goal

Establish the sole typed source for request/response envelopes, pagination, requestId, errors, and permission actions without inventing domain endpoints.

### Inputs

Architecture contract conventions.

### Files To Inspect

`packages/contracts` skeleton and architecture §11.

### Files To Create

Contract primitives, schema validator setup, error-code registry skeleton, permission-action type, contract tests.

### Files To Modify

Package exports.

### Implementation Steps

1. Define success/error/requestId envelopes and pagination primitives.
2. Define stable validation mechanism shared by API and clients.
3. Define permission Action registry with compile-time uniqueness.
4. Add compatibility/snapshot tests that reject accidental breaking changes.

### Commands

```bash
pnpm --filter @aisenhub/contracts test
pnpm --filter @aisenhub/contracts typecheck
```

### Tests

Valid/invalid envelope parsing, error-code uniqueness, permission-action uniqueness, serialization stability.

### Acceptance Criteria

- [ ] Contracts package has no app/database dependency.
- [ ] Invalid payloads fail validation.
- [ ] RequestId and stable error shape are mandatory.
- [ ] Tests/typecheck pass.

### Failure Recovery

Resolve schema-library typing/version issues without moving validation into individual apps.

### Do Not

Do not add unapproved domain fields or expose database errors.

### Output

Contract primitives ready for phase-specific schemas.

### Human Gate

None.

### Commit

`feat(contracts): add platform contract primitives` — Task P0-T008.

### Next

P0-T009.

## P0-T009 — Define platform-client and admin-client transport skeletons

Status: pending  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: client  
Track: C  
Parallel Safe: no

### Architecture References

- Main architecture §6 package boundaries
- §11.2 contract rules
- §15.2 Provider/client responsibilities

### Dependencies

P0-T008.

### Goal

Create shared HTTP transports with credentials, CSRF/requestId/error handling extension points while keeping product and Admin clients isolated.

### Inputs

Contract primitives and environment URL convention.

### Files To Inspect

Both client skeletons and contracts exports.

### Files To Create

Transport modules, typed error classes, mock-server tests.

### Files To Modify

Client package exports and app placeholders.

### Implementation Steps

1. Implement base URL injection and `credentials: include`.
2. Parse/validate contract envelopes and map stable errors.
3. Add in-memory CSRF hook and requestId propagation.
4. Add Admin-only Idempotency-Key helper without business methods.
5. Enforce no Admin import from platform-client and no Supabase imports.

### Commands

```bash
pnpm --filter @aisenhub/platform-client test
pnpm --filter @aisenhub/admin-client test
pnpm boundaries:check
```

### Tests

Mock success/error/malformed responses, cookie credentials, CSRF injection, requestId capture, and dependency boundaries.

### Acceptance Criteria

- [ ] Both clients depend only on contracts/shared tooling.
- [ ] Malformed API payloads fail safely.
- [ ] Admin transport can attach idempotency keys.
- [ ] No endpoint/business method is guessed.

### Failure Recovery

Fix transport abstraction and mocks; do not introduce a second generated client framework without need.

### Do Not

Do not store JWT/CSRF in persistent browser storage or access Supabase directly.

### Output

Typed transport skeletons.

### Human Gate

None.

### Commit

`feat(client): add typed platform transports` — Task P0-T009.

### Next

P0-T010.

## P0-T010 — Implement one-command Local verification orchestration

Status: completed  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: automation  
Track: F/G  
Parallel Safe: no

### Architecture References

- Main architecture §16 tests
- §18 Local environment
- §19 Platform Phase 0 acceptance

### Dependencies

P0-T005, P0-T006, P0-T007, P0-T008, P0-T009.

### Goal

Create `pnpm platform:verify` as the deterministic Local gate orchestrator.

### Inputs

All root scripts, Supabase lifecycle, test harnesses, package graph.

### Files To Inspect

Root scripts/configs and Local docs.

### Files To Create

Minimal orchestration script if package scripts alone cannot provide cleanup/error handling.

### Files To Modify

`package.json`, Local development documentation.

### Implementation Steps

1. Check/start Supabase Local without hiding startup failures.
2. Reset DB, apply migrations, seed, and generate types.
3. Run SQL/RLS/function/unit/contract/typecheck/lint/build/boundary/secret checks.
4. Guarantee nonzero exit on first failure and useful summaries.
5. Avoid destructive cleanup outside Local project paths.

### Commands

```bash
pnpm platform:verify
```

### Tests

Run once from clean Local state and once from already-running state; introduce one temporary failing fixture to verify failure propagation, then remove it.

### Acceptance Criteria

- [ ] One command executes the documented Local gate.
- [ ] Clean and warm runs exit 0.
- [ ] A failing subcheck makes the command fail.
- [ ] Generated types have no uncommitted drift after the second run.

### Failure Recovery

Fix ordering/readiness/cleanup; do not skip failing categories.

### Do Not

Do not contact Staging/Production or run broad destructive filesystem commands.

### Output

Deterministic `platform:verify`.

### Human Gate

None.

### Commit

`chore(verify): add autonomous local quality command` — Task P0-T010.

### Next

P0-T011.

## P0-T011 — Add CI parity and secret/dependency scans

Status: completed  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: CI/security  
Track: F/G  
Parallel Safe: yes

### Architecture References

- Main architecture §16.5 Security tests
- §18 release order

### Dependencies

P0-T010.

### Goal

Mirror Local verification in CI without external cloud secrets.

### Inputs

`platform:verify`, pinned tools, repository hosting convention discovered at execution.

### Files To Inspect

Existing CI directory and root scripts.

### Files To Create

CI workflow, secret scan config, dependency-boundary CI check.

### Files To Modify

Development docs and progress.

### Implementation Steps

1. Configure Docker/Supabase-compatible CI with dependency caching.
2. Run the same Local gate or equivalent ordered commands.
3. Add secret and forbidden-import scans.
4. Upload concise test artifacts on failure without sensitive logs.

### Commands

```bash
pnpm platform:verify
pnpm secrets:check
pnpm boundaries:check
```

### Tests

Validate workflow syntax locally where tooling permits and run all invoked scripts.

### Acceptance Criteria

- [ ] CI requires no Supabase Cloud secret.
- [ ] CI and Local gates have parity.
- [ ] Secret and Admin direct-access scans are blocking.
- [ ] Workflow/config validation passes.

### Failure Recovery

Repair runner services/caching while preserving checks; do not add secrets to make CI pass.

### Do Not

Do not deploy from bootstrap CI.

### Output

Zero-secret CI quality gate.

### Human Gate

None unless repository authorization is genuinely unavailable; local work must continue and H1 is documented only then.

### Commit

`ci(platform): enforce local parity and security scans` — Task P0-T011.

### Next

P0-T012.

## P0-T012 — Execute Bootstrap quality gate and checkpoint

Status: completed  
Phase: P0 — Autonomous Bootstrap  
Execution: AUTONOMOUS  
Type: quality-gate  
Track: F/G  
Parallel Safe: no

### Architecture References

- Main architecture §16
- §19 Platform Phase 0 acceptance
- Agent Execution Rules §8

### Dependencies

P0-T001, P0-T002, P0-T003, P0-T004, P0-T005, P0-T006, P0-T007, P0-T008, P0-T009, P0-T010, P0-T011.

### Goal

Prove the zero-human foundation and create the first auditable checkpoint.

### Inputs

Completed Bootstrap tasks and commits.

### Files To Inspect

All P0 outputs, progress, ledger.

### Files To Create

`docs/implementation/checkpoints/PHASE-00.md`.

### Files To Modify

`PROGRESS.md`, `TASK_LEDGER.md`.

### Implementation Steps

1. Run full verification from clean state.
2. Record PASS/FAIL/N/A with commands and timestamp.
3. Repair any failure and rerun the entire gate.
4. Record Git range, delivered files, limitations, deviations, human interventions, and next phase.

### Commands

```bash
pnpm platform:verify
git status --short
```

### Tests

Full P0 gate: reset, seed, type generation, SQL/RLS/function/unit/contract/typecheck/lint/build/E2E-list/security/boundaries.

### Acceptance Criteria

- [ ] `pnpm platform:verify` exits 0 from clean state.
- [ ] Checkpoint contains actual evidence and `Architecture Deviations: None` or approved reference.
- [ ] Ledger has one row/commit for every P0 task.
- [ ] Progress points to P1-T001.
- [ ] Human interactions used: 0.

### Failure Recovery

Return to the owning failed task, fix it, update history, and rerun the complete gate.

### Do Not

Do not mark the phase complete with skipped applicable checks or uncommitted generated drift.

### Output

PHASE-00 checkpoint and ready P1 state.

### Human Gate

None.

### Commit

`chore(checkpoint): complete platform bootstrap` — Task P0-T012.

### Next

P1-T001.
