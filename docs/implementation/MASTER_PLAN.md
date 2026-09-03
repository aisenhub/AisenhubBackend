# AisenHub Breaking Rebuild — Master Plan

## Overall Goal

Turn the current repository into the clean first release of the Unified Identity Platform with the least compatibility work possible.

This plan assumes:

```text
real production users = 0
required production business data = 0
external API/client compatibility obligations = 0
```

Therefore the implementation is a **breaking rebuild**, not a migration program.

## Architecture Authority

`../AISENHUB_UNIFIED_IDENTITY_PLATFORM_ARCHITECTURE_V2.md`

## What is deliberately removed

```text
/v1 old-auth + /v2 new-auth dual stack
legacy Platform Session compatibility
shared Cookie SSO
Origin as authenticated Application identity
legacy Session/Membership backfill
pilot-by-pilot migration machinery
legacy retirement phase
historical migration preservation
process-document accumulation
```

## What is deliberately preserved

```text
PostgreSQL transaction authority
RLS/private-schema boundaries
Catalog/Entitlement/Redemption/Commerce domain semantics
Admin backend RBAC/MFA/Business Commands
Audit/idempotency
Contracts/clients as stable boundaries
modular monolith
```

## Phase Map

| Phase | File | Result |
| --- | --- | --- |
| R0 | [Documentation and Architecture Reset](./phases/00-docs-architecture-reset.md) | Clean the documentation authority, archive only historically useful design/plan context, remove process-record clutter, and make the breaking-rebuild assumptions impossible to misread before runtime changes begin. |
| R1 | [Identity, Membership and OAuth Client Foundation](./phases/01-identity-membership-oauth-foundation.md) | Rebuild the data model around Global Identity + Application Membership + OAuth Client Binding, with no legacy user/session migration. |
| R2 | [OAuth, Auth Kernel and API Breaking Rebuild](./phases/02-oauth-auth-kernel-api-rebuild.md) | Replace shared Cookie Session authentication with OAuth/OIDC token-derived Application Context and make the clean `/v1` API use the new semantics directly. |
| R3 | [Account, Admin and Business-domain Integration](./phases/03-account-admin-domain-integration.md) | Connect the new identity context to Account Center, Admin and all existing business domains, then prove two independent applications work against one user platform. |
| R4 | [Clean Baseline, Dead-code Removal and Security Hardening](./phases/04-clean-baseline-hardening.md) | After behavior is correct, remove historical implementation baggage, modularize shared code, squash migrations and make a clean-from-zero rebuild the only supported development baseline. |
| R5 | [Fresh Staging and Production Release](./phases/05-fresh-staging-production.md) | Deploy the clean baseline as a fresh platform, prove OAuth across independent domains, then perform an explicitly approved Production deployment without carrying legacy migration machinery. |

## Critical Path

```text
R0-T008
 -> R1-T008
 -> R2-T008
 -> R3-T008
 -> R4-T007
 -> R5-T001
 -> R5-T002
 -> HG-002
 -> R5-T004
 -> R5-T005
```

## Parallel Work

Tasks may run in parallel only when dependencies permit and they do not edit the same migration, shared contract, auth kernel, lockfile, generated types or architecture docs.

Prefer sequential work for the Auth/Data foundation because the project is small and avoiding merge/rework saves more time than maximizing concurrency.

## Human Interaction

Only `HUMAN_GATES.md` may stop autonomous execution.

- Local: zero routine interaction.
- Staging: autonomous when current access exists.
- Provider/cloud authorization: HG-001 only if actually missing.
- Production destructive fresh deploy: HG-002 mandatory.
- DNS/real payments: HG-003 only when going live commercially.

## How progress is recovered without PROGRESS.md

A new Agent determines state by:

1. reading architecture/plan/current phase;
2. reading recent Git commits for task IDs;
3. inspecting current code and tests;
4. executing the acceptance tests for uncertain tasks.

Git is the implementation history. Docs are not a diary.

## Completion Definition

The rebuild is complete when:

- `auth.users` is Global Identity;
- Application Membership controls app user populations;
- verified OAuth `client_id` determines authenticated Application context;
- independent products do not share cookies;
- Platform Session legacy auth is gone;
- the clean `/v1` API uses only new auth semantics;
- Account, Admin, Entitlement, Redemption, Commerce, Feedback and deletion use the new context;
- migrations are a clean baseline series rebuildable from zero;
- full Local and Staging OAuth/security/E2E gates pass;
- Production is deployed only after HG-002;
- active docs contain no migration-era compatibility plan or process-record clutter.
