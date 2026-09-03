# AisenHub Platform Human Gates

> Budget: Local `0`; Staging `0–1` consolidated interaction; Production explicit approval gates.

## Gate state model

`planned → ready → waiting → resolved` or `skipped`.

A gate becomes `ready` only after the Agent has completed all autonomous prerequisites and verified that existing authorization/environment cannot satisfy it.

## HG-001 — Consolidated Staging Bootstrap

Status: resolved
Stage: Staging Bootstrap  
Category: H1/H2/H3/H4  
Maximum interactions: 1

Trigger only if the Agent cannot use existing authorization/resources after checking:

- Supabase CLI authentication and accessible Staging projects;
- expected Staging project/ref variables without printing values;
- hosting/Cloudflare/Vercel authorization already present;
- whether Staging DNS already exists or a temporary provider URL can complete smoke tests.

Before triggering, the Agent must have completed all Local phase gates, produced a deterministic migration/seed, passed API/Admin/Playwright tests, and prepared a single list of missing items.

Possible human action, requested together:

- authorize the required CLI/account;
- create or authorize a Staging Supabase/hosting resource if the Agent lacks permission;
- configure named Staging environment variables in the designated environment;
- approve/create Staging DNS only if provider URLs are insufficient for the required cross-origin test.

Secrets must never be pasted into chat. If authorization and resources already exist, mark this gate `skipped` and continue automatically.

## HG-002 — Commercial Configuration Freeze

Status: deferred
Stage: Before real sale/payment activation  
Category: H5  
Maximum interactions: 1 consolidated decision

Needed only for unresolved commercial commitments from architecture §22:

- official product price/currency and payment channel;
- whether purchases include future versions/tools and exact sales wording;
- partial-refund policy: compensation versus product return;
- all-site and remove-ads promises;
- AI/cloud cost policy;
- jurisdiction-specific retention periods.

The Agent may implement all model/state-machine behavior with deterministic non-production fixtures before this gate. It must not invent production commercial promises.

Current outcome: deferred for the Staging/test-only release scope. No price,
payment channel, sales promise, refund policy, cost policy, or jurisdictional
retention period is frozen. Resolve this gate as one consolidated decision
before creating formal Production products or accepting real money.

## HG-003 — Production Infrastructure and Secrets Authorization

Status: ready  
Stage: Production readiness  
Category: H1/H2/H3  
Maximum interactions: 1

Trigger only after Staging quality/smoke gates pass. Batch all missing production account authorization, project/resource access, and named environment variables. The Agent must provide a no-secret checklist and verify configuration without echoing values.

If the Agent already has the required scoped authorization and resources, this gate may be skipped, but HG-004 remains mandatory.

Current outcome: ready after P8-T002 read-only inspection. Supabase CLI
authorization is available and a separate healthy project candidate is
visible, but no protected `PRODUCTION_*` variables or Production origins are
configured. Production hosting CLI access and canonical DNS readiness are also
unavailable. The complete no-secret missing-item bundle is recorded in
`docs/implementation/PRODUCTION_BASELINE.md`. HG-004 remains a separate
mandatory deployment approval.

## HG-004 — Production Migration and Deployment Approval

Status: planned  
Stage: Production deployment  
Category: H6  
Maximum interactions: 1 explicit approval

Before asking, provide:

- exact migration/deployment plan and immutable artifact versions;
- Staging evidence and production preflight results;
- backup/recovery point verification;
- rollback/forward-fix plan;
- smoke tests and stop conditions;
- list of migrations, functions, apps, and configuration affected.

Without explicit approval, the Agent may prepare and dry-run only; it must not apply production migrations or deploy production services.

## HG-005 — Production DNS and Payment Cutover

Status: planned  
Stage: Production cutover  
Category: H4/H6  
Maximum interactions: 1 explicit approval

Required before changing `api.aisenhub.com`, `account.aisenhub.com`, `admin.aisenhub.com`, enabling real payment webhooks, or accepting real money. Batch DNS and payment cutover where practical. Prepare TTL/record changes, certificate checks, webhook verification, smoke tests, monitoring, and reversal steps first.

If no real payment or DNS cutover is part of the first release, keep this gate planned and complete the platform through Staging.

## Expected Human Intervention Summary

| Stage | Expected | Purpose | Skippable when |
| --- | ---: | --- | --- |
| Local Foundation | 0 | Fully automated Docker/Supabase/tests | Always zero under normal local permissions |
| Core Platform Local | 0 | Fixtures, Auth, API, DB, RLS and E2E are automated | Always zero |
| Admin Local | 0 | Role fixtures and Playwright verify UI/API | Always zero |
| Staging | 0–1 | Consolidated authorization/resources/secrets/DNS | Skip if current CLI/env/resources are usable |
| Commercial freeze | 0–1 | Real prices, promises, refund and retention policy | Defer while using test fixtures/no real sale |
| Production setup | 0–1 | Production authorization/resources/secrets | Skip if already available and scoped |
| Production deploy | 1 mandatory | Approve production migration/deployment risk | Never skipped for first production deployment |
| DNS/payment cutover | 0–1 | Approve real traffic/money cutover | Defer if not going live |
