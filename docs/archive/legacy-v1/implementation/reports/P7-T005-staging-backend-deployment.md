# P7-T005 Staging Backend Deployment Report

Date: 2026-09-02
Environment: Staging project `workendstaging` (`egsokuicabbxspkdccqe`)

## Deployment

- All 41 repository migrations were applied to the Staging database.
- Remote migration history matches the local migration set exactly.
- The six repository Edge Functions are deployed and ACTIVE:
  `platform-public`, `platform-api`, `platform-admin`, `payment-webhook`,
  `account-deletion-worker`, and `retention-cleanup`.
- Functions were deployed with platform JWT verification disabled because the
  application handlers own the documented authentication, Origin, CSRF, and
  service-worker checks.

## Verification

- `pnpm staging:preflight --check-only`: PASS; all nine required variables are present.
- The configured anon and service-role keys match the selected Staging project without printing values.
- Staging Auth admin read check: HTTP 200.
- Public catalog endpoint: HTTP 200 with an empty catalog response.
- Exact Account/Admin Vercel Origins are registered as active Staging Origins.
- `GET /v1/session` with the Account Vercel Origin returns HTTP 200 and an anonymous session projection.
- The deployed Account page now renders its sign-in form after the Origin fix.
- The designated Staging Auth account signs in with HTTP 200, exchanges a Platform Session with HTTP 201, and receives an Admin Session with HTTP 200 and role `admin`.

## Follow-up

Browser-security verification is recorded in
`docs/implementation/reports/P7-T007-staging-browser-security.md`.

No Production resource was contacted or changed. No secret value is recorded here.

Architecture Deviations: None.
