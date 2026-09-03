# Legacy V1 Plan and Task Archive Summary

The former implementation program contained **107 tasks** across P0–P8.

| Phase | Historical purpose |
| --- | --- |
| P0 | Workspace, Local Supabase, contracts, CI and deterministic verification |
| P1 | Profiles, Applications/Origins, Platform Session, Account auth, CORS/CSRF |
| P2 | Catalog, Entitlement, Redemption |
| P3 | Admin foundation, RBAC, providers and read operations |
| P4 | Admin catalog/customer operations and product integration |
| P5 | Commerce, payments, refunds, chargebacks and webhook flow |
| P6 | Deletion, retention, telemetry, security/performance hardening |
| P7 | Staging deployment and smoke/recovery proof |
| P8 | Production readiness and explicit release gates |

The old phase/task Markdown files are not copied as active instructions because they contain obsolete implementation assumptions. `SOURCE_MANIFEST.md` records their exact historical paths and blob SHAs so the full originals can be recovered from Git when needed.

The new Breaking Rebuild preserves the proven domain/security outcomes while replacing the authentication topology directly.
