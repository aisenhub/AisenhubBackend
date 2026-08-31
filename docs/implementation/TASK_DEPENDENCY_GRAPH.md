# AisenHub Platform Task Dependency Graph

> Task files remain authoritative for exact dependency text. An edge means the target cannot start until the source is completed. Tasks marked `Parallel Safe: yes` may run concurrently only when they do not edit the same shared contract, migration, lockfile, or progress files.

## P0 — Bootstrap

```mermaid
flowchart LR
  T001[P0-T001] --> T002[P0-T002] --> T003[P0-T003]
  T003 --> T004[P0-T004] --> T005[P0-T005] --> T006[P0-T006] --> T007[P0-T007]
  T003 --> T008[P0-T008] --> T009[P0-T009]
  T005 --> T010[P0-T010]
  T006 --> T010
  T007 --> T010
  T008 --> T010
  T009 --> T010
  T010 --> T011[P0-T011] --> T012[P0-T012 Gate]
```

Parallel lane: P0-T004 database/runtime and P0-T008 contracts may proceed after P0-T003; merge before P0-T010.

## P1 — Identity / Application / Session

```mermaid
flowchart LR
  A[P1-T001 Profiles] --> B[P1-T002 Apps/Origins]
  A --> C[P1-T003 Sessions/Admin]
  B --> D[P1-T004 RLS]
  C --> D
  C --> E[P1-T005 Contracts]
  D --> F[P1-T006 Reads]
  E --> F
  E --> G[P1-T007 Exchange] --> H[P1-T008 Lifecycle]
  B --> I[P1-T009 CORS]
  H --> I --> J[P1-T010 CSRF]
  E --> K[P1-T011 Account]
  G --> K
  J --> K
  F --> L[P1-T012 E2E]
  K --> L --> M[P1-T013 Security Matrix] --> N[P1-T014 Gate]
```

Parallel lanes: schema/contract preparation and account shell can proceed where dependencies allow; all converge at P1-T012.

## P2 — Catalog / Entitlement / Redemption

```mermaid
flowchart LR
  A[P2-T001 Catalog] --> B[P2-T002 Features/Prices] --> C[P2-T003 Catalog Commands]
  B --> D[P2-T004 Grants] --> E[P2-T005 Grant Commands] --> F[P2-T006 Access]
  B --> G[P2-T007 Redemption Schema] --> H[P2-T008 Generate]
  E --> I[P2-T009 Redemption Tests]
  H --> I --> J[P2-T010 Redeem]
  C --> K[P2-T011 Product APIs]
  F --> K
  J --> K --> L[P2-T012 platform-client]
  C --> M[P2-T013 Admin Contracts]
  J --> M
  K --> N[P2-T014 Seed] --> O[P2-T015 E2E]
  L --> O
  M --> O
  O --> P[P2-T016 Gate]
```

Parallel lanes: Catalog state, Entitlement state, and Redemption storage are separate until transaction/API integration.

## P3 — Admin Foundation

```mermaid
flowchart LR
  A[P3-T001 Workspace] --> D[P3-T004 Data Provider]
  A --> E[P3-T005 Command Client]
  A --> G[P3-T007 Ant Theme]
  B[P3-T002 Admin Session] --> C[P3-T003 Actions]
  C --> F[P3-T006 Auth/Access Providers]
  D --> F
  F --> H[P3-T008 Shell]
  G --> H
  B --> I[P3-T009 Query API]
  H --> J[P3-T010 UI/RBAC E2E]
  I --> J --> K[P3-T011 Gate]
```

Parallel lanes: Backend Admin auth/query, client Providers, and Ant Design theme can proceed independently before shell/E2E integration.

## P4 — Admin B/C and Product Integration

```mermaid
flowchart LR
  A[P4-T001 Queries] --> B[P4-T002 Drafts] --> C[P4-T003 Catalog Commands]
  A --> D[P4-T004 Redemption Commands]
  C --> E[P4-T005 Dangerous UI]
  D --> E
  E --> F[P4-T006 Catalog UI]
  E --> G[P4-T007 Redemption UI]
  H[P4-T008 Deletion Foundation] --> I[P4-T009 User Overview] --> J[P4-T010 Customer Commands] --> K[P4-T011 Customer UI]
  J --> L[P4-T012 Account/AisenLens]
  F --> M[P4-T013 E2E]
  G --> M
  K --> M
  L --> M --> N[P4-T014 Gate]
```

Parallel lanes: Catalog/Redemption operations and Customer/deletion operations converge only at cross-system E2E.

## P5 — Commerce

```mermaid
flowchart LR
  A[P5-T001 Orders] --> B[P5-T002 Payments] --> C[P5-T003 State Tests]
  B --> D[P5-T004 Contracts]
  C --> E[P5-T005 Fulfillment]
  D --> E
  E --> F[P5-T006 Verify]
  E --> G[P5-T007 Refund] --> H[P5-T008 Exceptions]
  H --> I[P5-T009 Webhook]
  G --> J[P5-T010 Queries]
  H --> J --> K[P5-T011 Admin UI]
  F --> K
  I --> L[P5-T012 E2E]
  K --> L --> M[P5-T013 Gate]
```

## P6 — Operations Hardening

```mermaid
flowchart LR
  A[P6-T001 Deletion] --> B[P6-T002 Retention]
  C[P6-T003 Telemetry] --> D[P6-T004 Dashboard] --> E[P6-T005 Filters] --> F[P6-T006 A11y/Perf]
  B --> G[P6-T007 Security Audit]
  F --> G --> H[P6-T008 Release E2E]
  H --> I[P6-T009 Docs] --> J[P6-T010 Gate]
```

## P7 — Staging

```mermaid
flowchart LR
  A[P7-T001 Inspect] --> B[P7-T002 Bundle]
  A --> C[P7-T003 HG-001 conditional]
  B --> D[P7-T004 Configure]
  C --> D --> E[P7-T005 Backend Deploy]
  E --> F[P7-T006 Apps Deploy] --> G[P7-T007 Browser Security]
  G --> H[P7-T008 Smoke/Recovery] --> I[P7-T009 Gate]
```

P7-T003 is skipped automatically when authorization/resources already exist; it is the only Staging Human Gate.

## P8 — Production Readiness

```mermaid
flowchart LR
  A[P8-T001 HG-002 conditional]
  B[P8-T002 Inspect] --> C[P8-T003 HG-003 conditional]
  A --> D[P8-T004 Release Dossier]
  C --> D --> E[P8-T005 HG-004 mandatory]
  E --> F[P8-T006 Deploy]
  F --> G[P8-T007 HG-005 conditional cutover]
  G --> H[P8-T008 Final Checkpoint]
  F --> H
```

Production deployment never starts before P8-T005 explicit approval. Cutover may remain deferred while P8-T008 reports a Staging-verified or deployed-but-not-live state.
