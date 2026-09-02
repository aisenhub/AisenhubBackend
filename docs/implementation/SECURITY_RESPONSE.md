# Security Response Runbook

This is the operational response for suspected Platform boundary, credential,
session, payment, redemption, or entitlement exposure.

## Immediate handling

1. Stop the affected Local/Staging job or deployment; do not make a production
   change without the applicable Human Gate.
2. Preserve the request ID, timestamp, route, stable error code, commit SHA, and
   test artifact path. Do not copy tokens, cookies, raw payment payloads,
   redemption plaintext, or secret values into the incident record.
3. Determine whether the event is Local, Staging, or Production. Never reuse
   database, webhook, OAuth, payment, or redemption credentials across these
   environments.
4. Run the smallest safe evidence checks:

```bash
pnpm test:security
pnpm secrets:check
pnpm boundaries:check
pnpm test:harness:negative
```

## Investigation boundaries

Check the Platform Backend/API and authoritative audit record first. Confirm
that the affected path has runtime validation, Origin/App/session/CSRF checks,
authorization, stable error mapping, and a request ID. Confirm that Admin and
Account still use HTTP Contracts rather than Supabase Data API, table imports,
or service-role credentials.

For redemption or payment concerns, verify that only digests/minimized summaries
are persisted and that idempotency/concurrency behavior remains atomic. For
identity concerns, verify session revocation, profile state, and the
service-only deletion/retention path.

## Recovery and closure

Credential rotation, external account access, production deployment, DNS, and
data-preserving rollback are authorized operations, not ad-hoc debugging. Use
the approved secret manager and record the rotation/deploy evidence without
revealing values.

Close the incident only after the focused regression test, full applicable Local
quality gate, documentation/ledger update, and commit range are recorded. If a
safe fix would require changing the formal architecture, create an
`ARCHITECTURE_BLOCKER` instead of silently changing the model or boundary.

Architecture Deviations: None
