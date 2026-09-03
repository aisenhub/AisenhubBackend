# AisenHub Unified Identity Platform V2 — Master Plan

The V2 architecture is the authority for this plan. Implementation must be
incremental and must preserve the existing Commerce, Entitlement, Redemption,
Audit, Idempotency, RLS, and Admin safety guarantees until their V2-compatible
replacements are verified.

## Migration phases

1. Phase A — Architecture freeze and repository boundary update
2. Phase B — Application Membership foundation
3. Phase C — OAuth/OIDC client and redirect URI registry
4. Phase D — Auth context and application authorization kernel
5. Phase E — Account Center and application membership UI
6. Phase F — Platform SDK and BFF adapters
7. Phase G — Pilot migration of one application
8. Phase H — Existing application migration
9. Phase I — Legacy Platform Session retirement

No phase is considered complete without its applicable database, RLS,
contract, API, integration, browser, security, and build checks.
