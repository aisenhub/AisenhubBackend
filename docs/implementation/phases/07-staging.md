# Phase P7 — Staging Bootstrap and Verification

Goal: deploy and verify the Local release candidate in isolated Staging. Human Interaction Budget: **0–1 consolidated interaction**, only through HG-001 when existing authorization/resources are insufficient.

## P7-T001 — Inspect existing Staging authorization and resources

Status: pending  
Phase: P7 — Staging  
Execution: AUTONOMOUS  
Type: discovery  
Track: G  
Parallel Safe: no

### Architecture References

- Main §18.1 environments
- Human Gates HG-001
- Agent Rules §6

### Dependencies

P6-T010.

### Goal

Determine without prompting whether Supabase/hosting/DNS Staging access and named variables already exist.

### Inputs

Current CLI sessions, environment variable names, accessible projects.

### Files To Inspect

- deployment configs
- `.env.example`
- CLI auth status without printing tokens

### Files To Create

- `docs/implementation/STAGING_BASELINE.md`

### Files To Modify

- `HUMAN_GATES.md`
- `PROGRESS.md`

### Implementation Steps

1. Check Supabase CLI auth/projects.
2. Check hosting/Cloudflare/Vercel auth only for selected existing deployment path.
3. Check required variable presence by name/boolean.
4. Check existing Staging DNS and provider URLs.
5. Classify all missing items in one HG-001 bundle.

### Commands

```bash
supabase projects list
pnpm staging:preflight --check-only
```

### Tests

Preflight must redact values and distinguish missing auth/resource/config.

### Acceptance Criteria

- [ ] Baseline lists usable and missing capabilities.
- [ ] No secret value is printed/stored.
- [ ] HG-001 is marked skipped or ready exactly once.
- [ ] Independent work continues.

### Failure Recovery

Retry safe checks/deploy steps, inspect provider output, and forward-fix Staging within the approved release plan. Never expose secrets. Record material failures in progress/checkpoint.

### Do Not

Do not ask one credential at a time or create Production resources.

### Output

Staging capability baseline.

### Human Gate

No immediate gate; prepare HG-001 only if checks prove it necessary.

### Commit

`docs(staging): record environment capability baseline` — Task P7-T001.

### Next

P7-T002; P7-T003 only if HG-001 is ready.

## P7-T002 — Build immutable Staging deployment bundle and preflight

Status: pending  
Phase: P7 — Staging  
Execution: AUTONOMOUS  
Type: release  
Track: G/F  
Parallel Safe: yes

### Architecture References

- Main §18.3 release order
- §18.4 compatibility
- §18.5 migration

### Dependencies

P7-T001.

### Goal

Produce versioned migrations/functions/apps and a no-secret preflight before connecting Staging.

### Inputs

PHASE-06 release candidate and Git commit.

### Files To Inspect

- CI artifacts
- migration history
- build outputs

### Files To Create

- Staging deployment manifest/checksum
- preflight script/tests

### Files To Modify

- release docs

### Implementation Steps

1. Pin exact Git SHA/artifact versions.
2. Validate migration order from empty and upgrade-like Staging baseline.
3. Build Edge Functions/account/admin.
4. Generate variable-name/DNS/CORS checklist.
5. Define stop/retry/recovery conditions.

### Commands

```bash
pnpm platform:verify
pnpm release:bundle --env staging
pnpm staging:preflight --offline
```

### Tests

Artifact checksums, clean build, migration dry run, config-name validation.

### Acceptance Criteria

- [ ] Bundle is reproducible from Git SHA.
- [ ] No Local secret enters artifacts.
- [ ] Preflight reports all requirements together.
- [ ] Tests pass.

### Failure Recovery

Retry safe checks/deploy steps, inspect provider output, and forward-fix Staging within the approved release plan. Never expose secrets. Record material failures in progress/checkpoint.

### Do Not

Do not deploy or mutate any remote resource yet.

### Output

Staging release bundle.

### Human Gate

None.

### Commit

`chore(release): prepare staging deployment bundle` — Task P7-T002.

### Next

P7-T003 or P7-T004.

## P7-T003 — Resolve consolidated HG-001 when Staging access is unavailable

Status: pending  
Phase: P7 — Staging  
Execution: HUMAN_GATE  
Type: human-gate  
Track: G  
Parallel Safe: no

### Architecture References

- Human Gates HG-001
- Agent Rules §5
- Main §18.1

### Dependencies

P7-T001,P7-T002.

### Goal

Obtain all genuinely missing Staging authorization/resources/configuration in one interaction.

### Inputs

STAGING_BASELINE and preflight checklist.

### Files To Inspect

- HG-001 evidence
- all auth/config checks

### Files To Create

- No source file beyond gate evidence.

### Files To Modify

- `HUMAN_GATES.md`
- `PROGRESS.md`
- `TASK_LEDGER.md`

### Implementation Steps

1. If nothing is missing, mark task/gate skipped and continue.
2. If missing, set HG-001 READY with completed Local evidence.
3. Ask once for all missing authorization/resource/variable/DNS actions; never request secret values in chat.
4. After user action, verify presence/access without printing values and mark resolved.
5. Resume automatically.

### Commands

```bash
pnpm staging:preflight --check-only
```

### Tests

Re-run consolidated preflight.

### Acceptance Criteria

- [ ] Gate is skipped or resolved.
- [ ] All required Staging capabilities are available.
- [ ] No secret has been disclosed.
- [ ] Only one Staging interaction was used.

### Failure Recovery

Retry safe checks/deploy steps, inspect provider output, and forward-fix Staging within the approved release plan. Never expose secrets. Record material failures in progress/checkpoint.

### Do Not

Do not trigger before Local completion or block on optional custom DNS when provider URL suffices.

### Output

Resolved/skipped HG-001.

### Human Gate

This is the sole planned Staging Human Gate. Agent must wait only if status becomes waiting.

### Commit

`docs(gate): resolve staging bootstrap authorization` — Task P7-T003.

### Next

P7-T004.

## P7-T004 — Link Staging projects and configure scoped secrets safely

Status: pending  
Phase: P7 — Staging  
Execution: AUTONOMOUS  
Type: environment  
Track: G  
Parallel Safe: no

### Architecture References

- Main §18.1 environment isolation
- §13.5 secrets
- root AGENTS §9

### Dependencies

P7-T002 completed; P7-T003 completed with HG-001 marked `skipped` or `resolved`.

### Goal

Connect Staging resources and configure named secrets without echoing or committing values.

### Inputs

Authorized project/resources and environment values.

### Files To Inspect

- Staging baseline
- secret manager/CLI status

### Files To Create

- non-secret Staging config references

### Files To Modify

- deployment config only

### Implementation Steps

1. Link exact Staging Supabase project.
2. Set Edge/hosting variables through scoped secret managers.
3. Use unique Staging pepper/webhook/test values.
4. Verify required names/presence and environment isolation.
5. Record resource IDs safe for docs.

### Commands

```bash
pnpm staging:configure
pnpm staging:preflight
```

### Tests

Presence/scope checks, no Production/Local project collision, repository secret scan.

### Acceptance Criteria

- [ ] Staging is linked to intended project.
- [ ] Environment secrets are isolated.
- [ ] No value appears in Git/log.
- [ ] Preflight passes.

### Failure Recovery

Retry safe checks/deploy steps, inspect provider output, and forward-fix Staging within the approved release plan. Never expose secrets. Record material failures in progress/checkpoint.

### Do Not

Do not reuse Production secrets or write `.env` into commits.

### Output

Safely configured Staging environment.

### Human Gate

None after HG-001 resolution.

### Commit

`chore(staging): configure scoped environment` — Task P7-T004.

### Next

P7-T005.

## P7-T005 — Deploy Staging database and Edge Functions

Status: pending  
Phase: P7 — Staging  
Execution: AUTONOMOUS  
Type: deployment  
Track: A/B/G  
Parallel Safe: no

### Architecture References

- Main §18.3 release order
- §18.4 compatibility

### Dependencies

P7-T004.

### Goal

Apply approved migrations and functions to Staging with verification and recovery evidence.

### Inputs

Staging bundle and linked project.

### Files To Inspect

- migration manifest
- recovery plan

### Files To Create

- deployment result record

### Files To Modify

- progress/ledger

### Implementation Steps

1. Capture pre-deploy schema/migration state.
2. Apply migrations in manifest order.
3. Run remote DB/RLS smoke tests.
4. Deploy versioned functions.
5. Run contract/function smoke; stop on failure and forward-fix/restore per plan.

### Commands

```bash
pnpm staging:deploy:db
pnpm staging:test:db
pnpm staging:deploy:functions
pnpm staging:test:api
```

### Tests

Migration status, DB constraints/RLS, function health/contracts.

### Acceptance Criteria

- [ ] All expected migrations applied once.
- [ ] Remote DB/API smoke passes.
- [ ] No seed contains Production data.
- [ ] Deployment evidence recorded.

### Failure Recovery

Retry safe checks/deploy steps, inspect provider output, and forward-fix Staging within the approved release plan. Never expose secrets. Record material failures in progress/checkpoint.

### Do Not

Do not reset Staging blindly or touch Production.

### Output

Verified Staging backend.

### Human Gate

None.

### Commit

`chore(staging): deploy backend release candidate` — Task P7-T005.

### Next

P7-T006.

## P7-T006 — Deploy account and Admin Staging applications

Status: pending  
Phase: P7 — Staging  
Execution: AUTONOMOUS  
Type: deployment  
Track: D/E/G  
Parallel Safe: yes

### Architecture References

- Main §18.3 release order
- §5 domain responsibilities

### Dependencies

P7-T005.

### Goal

Deploy versioned account/admin builds against Staging API with safe configuration.

### Inputs

Built artifacts and Staging API URL.

### Files To Inspect

- hosting config
- artifact manifest

### Files To Create

- deployment URL record

### Files To Modify

- progress

### Implementation Steps

1. Deploy account/admin immutable builds.
2. Set only public safe environment values in frontend.
3. Verify no service secret in bundles.
4. Register exact deployed origins through approved Admin/API path.
5. Run static/build smoke.

### Commands

```bash
pnpm staging:deploy:account
pnpm staging:deploy:admin
pnpm staging:scan:bundles
```

### Tests

Bundle secret/import scan, health/page loads, exact origin registration.

### Acceptance Criteria

- [ ] Both apps load against Staging API.
- [ ] Admin has no Supabase Data SDK/secret.
- [ ] Origins are exact.
- [ ] Tests pass.

### Failure Recovery

Retry safe checks/deploy steps, inspect provider output, and forward-fix Staging within the approved release plan. Never expose secrets. Record material failures in progress/checkpoint.

### Do Not

Do not place server secrets in Vite public env.

### Output

Staging account/Admin deployments.

### Human Gate

None.

### Commit

`chore(staging): deploy account and admin apps` — Task P7-T006.

### Next

P7-T007.

## P7-T007 — Finalize Staging origins, DNS, and browser security

Status: pending  
Phase: P7 — Staging  
Execution: AUTONOMOUS  
Type: environment-security  
Track: B/G/F  
Parallel Safe: no

### Architecture References

- Main §10.2 CORS
- §18 environments
- Human Gates HG-001

### Dependencies

P7-T006.

### Goal

Verify cross-origin Cookie/CORS/CSRF using real Staging hosts or provider URLs without creating a second gate.

### Inputs

Deployment URLs and any DNS action resolved in HG-001.

### Files To Inspect

- origin registry
- DNS/cert status

### Files To Create

- Staging browser-security report

### Files To Modify

- origin records through controlled API

### Implementation Steps

1. Use provider URLs if custom DNS is not required for valid tests.
2. If HG-001 included DNS, verify records/TLS now.
3. Register exact account/admin/test-tool origins.
4. Run credentialed CORS/CSRF/cookie checks.
5. Verify no wildcard/parent-domain cookie.

### Commands

```bash
pnpm staging:test:browser-security
pnpm staging:preflight
```

### Tests

TLS, exact Origin, preflight, Cookie flags/domain, CSRF, forged app header.

### Acceptance Criteria

- [ ] Browser security tests pass on actual hosts.
- [ ] No credentialed wildcard exists.
- [ ] No extra Human Gate is introduced.
- [ ] Evidence recorded.

### Failure Recovery

Retry safe checks/deploy steps, inspect provider output, and forward-fix Staging within the approved release plan. Never expose secrets. Record material failures in progress/checkpoint.

### Do Not

Do not modify Production DNS.

### Output

Verified Staging web security.

### Human Gate

None; any necessary Staging DNS authorization must have been batched into HG-001.

### Commit

`test(staging): verify browser security boundaries` — Task P7-T007.

### Next

P7-T008.

## P7-T008 — Run Staging smoke, E2E, observability, and recovery drill

Status: pending  
Phase: P7 — Staging  
Execution: AUTONOMOUS  
Type: verification  
Track: F/G  
Parallel Safe: no

### Architecture References

- Main §16 tests
- §17 observability
- §18 deployment

### Dependencies

P7-T005, P7-T006, P7-T007.

### Goal

Prove the release candidate remotely with isolated fixtures and a safe recovery exercise.

### Inputs

Staging backend/apps and test accounts.

### Files To Inspect

- Local release E2E
- Staging telemetry

### Files To Create

- Staging smoke report

### Files To Modify

- progress

### Implementation Steps

1. Create/refresh nonproduction fixture users/data through approved setup.
2. Run critical account/Admin/redemption/Commerce E2E.
3. Verify requestId/Audit/metrics/alerts.
4. Exercise a non-destructive recovery/failed deployment simulation.
5. Clean only designated test fixtures if safe.

### Commands

```bash
pnpm staging:test:smoke
pnpm staging:test:e2e
pnpm staging:test:observability
pnpm staging:test:recovery
```

### Tests

Critical release journey, role matrix, concurrency/idempotency, telemetry, rollback/forward-fix drill.

### Acceptance Criteria

- [ ] All Staging suites PASS.
- [ ] Telemetry links requestId to Audit.
- [ ] Recovery procedure is executable.
- [ ] No Production or real customer data used.

### Failure Recovery

Retry safe checks/deploy steps, inspect provider output, and forward-fix Staging within the approved release plan. Never expose secrets. Record material failures in progress/checkpoint.

### Do Not

Do not ask user to click/test or run destructive reset.

### Output

Staging verification evidence.

### Human Gate

None.

### Commit

`test(staging): complete remote smoke and recovery drill` — Task P7-T008.

### Next

P7-T009.

## P7-T009 — Execute Staging quality gate and checkpoint

Status: pending  
Phase: P7 — Staging  
Execution: AUTONOMOUS  
Type: quality-gate  
Track: F/G  
Parallel Safe: no

### Architecture References

- Master Completion Definition
- Human Interaction Budget

### Dependencies

P7-T001, P7-T002, P7-T003, P7-T004, P7-T005, P7-T006, P7-T007, P7-T008.

### Goal

Finalize PHASE-07 evidence and mark implementation Staging-verified.

### Inputs

All Staging reports/deployments.

### Files To Inspect

- deployment manifests
- smoke/security/recovery reports
- gate history

### Files To Create

- `checkpoints/PHASE-07.md`

### Files To Modify

- `PROGRESS.md`
- `TASK_LEDGER.md`
- `HUMAN_GATES.md`

### Implementation Steps

1. Re-run final Staging preflight/smoke.
2. Verify artifact-to-Git trace.
3. Record all PASS/FAIL/N/A, resources, Git range, intervention count.
4. Keep Production gates planned; do not deploy.

### Commands

```bash
pnpm staging:preflight
pnpm staging:test:smoke
git status --short
```

### Tests

Staging migration/API/browser/E2E/observability/recovery evidence.

### Acceptance Criteria

- [ ] All applicable Staging checks PASS.
- [ ] HG-001 used 0 or 1 interaction only.
- [ ] Architecture Deviations None or approved.
- [ ] Staging artifact is traceable to Git.
- [ ] Progress points to P8-T001.

### Failure Recovery

Retry safe checks/deploy steps, inspect provider output, and forward-fix Staging within the approved release plan. Never expose secrets. Record material failures in progress/checkpoint.

### Do Not

Do not treat Staging completion as production approval.

### Output

PHASE-07 checkpoint.

### Human Gate

None; HG-001 outcome is recorded.

### Commit

`chore(checkpoint): complete staging verification` — Task P7-T009.

### Next

P8-T001.
