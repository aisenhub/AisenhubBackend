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
- No Staging Auth users exist yet; therefore no Staging Admin membership exists.
- Requests carrying the deployed Vercel Origin currently receive `ORIGIN_NOT_ALLOWED` until exact Staging Origins are registered.

## Remaining bootstrap work

1. Create the intended non-production user through the Staging Account application.
2. Provision that user as `owner` or `admin` through the controlled bootstrap path.
3. Register the exact Account/Admin Vercel Origins as Staging Origins.
4. Run authenticated API, browser-security, and Staging E2E smoke tests.

No Production resource was contacted or changed. No secret value is recorded here.

Architecture Deviations: None.
