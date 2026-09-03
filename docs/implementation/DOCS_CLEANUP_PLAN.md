# Documentation Cleanup and Archive Plan

This file defines the exact docs cleanup target for the breaking rebuild.

## 1. Current repository snapshot

At the reviewed `main` snapshot, active `docs/` contains:

```text
AISENHUB_UNIFIED_IDENTITY_PLATFORM_ARCHITECTURE_V2.md
ARCHITECTURE_CHANGELOG.md
README.md
archive/
implementation/
```

The repository has already moved the former V1 architecture and P0–P8 evidence under `docs/archive/legacy-v1/`.

## 2. Curated archive policy

Keep historical **design** and **plan intent**. Remove routine execution evidence.

### Preserve conceptually

Legacy V1:

- main backend architecture;
- Admin architecture;
- architecture consistency decision;
- Master Plan phase map;
- Human Gate model;
- task dependency/phase design;
- phase/task source SHAs so exact originals remain recoverable from Git.

Superseded migration-oriented V2:

- the previous V2 architecture source SHA;
- previous V2 Master Plan source SHA;
- a concise explanation of why the compatibility migration was superseded.

### Remove from the curated docs tree

These are process records or obsolete operational snapshots:

```text
archive/legacy-v1/implementation/PROGRESS.md
archive/legacy-v1/implementation/TASK_LEDGER.md
archive/legacy-v1/implementation/ENVIRONMENT_BASELINE.md
archive/legacy-v1/implementation/PRODUCTION_BASELINE.md
archive/legacy-v1/implementation/PRODUCTION_ENV_FILL_TEMPLATE.md
archive/legacy-v1/implementation/STAGING_BASELINE.md
archive/legacy-v1/implementation/STAGING_BASELINE.zh-CN.md
archive/legacy-v1/implementation/STAGING_ENV_FILL_TEMPLATE.md
archive/legacy-v1/implementation/API_GENERATION.md
archive/legacy-v1/implementation/LOCAL_DEVELOPMENT.md
archive/legacy-v1/implementation/OPERATIONS_RUNBOOK.md
archive/legacy-v1/implementation/SECURITY_RESPONSE.md
archive/legacy-v1/implementation/TELEMETRY.md
archive/legacy-v1/implementation/blockers/**
archive/legacy-v1/implementation/checkpoints/**
archive/legacy-v1/implementation/reports/**
```

The exact deleted content remains recoverable through Git history and the source commit manifest; it does not need to remain in the active repository tree.

## 3. Replace the current implementation placeholders

Delete/replace the migration-oriented current files:

```text
implementation/MASTER_PLAN.md
implementation/PROGRESS.md
implementation/TASK_LEDGER.md
```

`PROGRESS.md` and `TASK_LEDGER.md` are not recreated.

The new implementation directory contains only stable instructions:

```text
README.md
MASTER_PLAN.md
AGENT_EXECUTION_RULES.md
HUMAN_GATES.md
DOCS_CLEANUP_PLAN.md
phases/*.md
```

## 4. Root AGENTS cleanup

The root `AGENTS.md` must be updated to remove obsolete assumptions such as:

- Platform Session as a general platform responsibility;
- `*.aisenhub.com` as the expected product-domain topology;
- old Session/Auth model immutability rules that conflict with this breaking rebuild.

Replace with:

```text
Global Identity
Application Membership
OAuth client-derived Application Context
independent application sessions/tokens
arbitrary application domains
```

## 5. Docs checker

`pnpm docs:check` should enforce:

- no active link to archived docs as implementation authority;
- no `PROGRESS.md`, `TASK_LEDGER.md`, `checkpoints/`, `reports/` under active implementation;
- all phase IDs unique;
- no references to `/v2` compatibility strategy;
- no active instruction to preserve legacy Platform Cookie Session;
- archive files include a historical/superseded banner or manifest.
