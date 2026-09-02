# P6-T008 Release-Candidate E2E Report

Date: 2026-09-02
Environment: Local Supabase and Docker-compatible runtime
Runner: Chromium, headless, one worker

## Scope

The deterministic release-candidate journey covers:

- normal-user sign-in, platform session and request IDs;
- public Catalog and server-resolved Entitlements;
- a valid Local-only Redemption code and safe response redaction;
- user Feedback submission with server-side application attribution;
- reauthenticated Account Deletion request and session sign-out;
- Owner User 360 projection of the resulting Redemption, Feedback, deletion
  request, and Audit timeline;
- Commerce resilience integration coverage for duplicate, out-of-order, partial
  refund, chargeback, late-payment, and audit outcomes.

## Commands and Evidence

The repeatable orchestrator is `pnpm test:e2e:release`. It performs one Local
database reset, verifies five deterministic Local Auth/domain fixtures, runs the
browser journey with `RELEASE-CANDIDATE`, and runs the focused Commerce
resilience suite.

| Check | Result |
| --- | --- |
| Local database reset | PASS |
| Deterministic fixtures | PASS — 5 users and Local catalog fixtures |
| `RELEASE-CANDIDATE` browser journey | PASS — 1/1 |
| Commerce resilience integration | PASS — 2/2 |

The browser artifact contains no production credentials. The Local test code is
stored only as an HMAC digest in the fixture SQL; the plaintext is supplied by
the test at runtime and is never persisted.

## Known Limitations

- Commerce browser command controls remain covered by the existing mocked Admin
  UI contract tests; stateful payment/refund/chargeback transitions are proved
  by the focused database and integration suites.
- Local Vite output still reports existing Ant Design deprecation notices; they
  do not affect this journey.

Architecture Deviations: None
