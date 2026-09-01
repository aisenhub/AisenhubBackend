# P1-T013 Security and Contract Matrix

Date: 2026-09-01  
Status: PARTIAL — current P1 routes verified; Admin Session is blocked by phase ownership.

## Verified Routes

| Route | Success coverage | Negative/security coverage |
| --- | --- | --- |
| `POST /v1/session/exchange` | Verified 201 exchange and profile identity | Missing/invalid bearer 401, disabled profile 403, hash-free response and Host-only cookie |
| `GET /v1/session` | Anonymous and authenticated reads | Unknown/expired/revoked session 401, CSRF rotation, no sensitive error details |
| `DELETE /v1/session` | Current-session revoke and cookie clear | Exact Origin/app declaration and session-bound CSRF required |
| `GET /v1/me` | Authenticated profile projection | Missing bearer 401 and stable error envelope |
| `GET /v1/apps/{slug}` | Active public application projection | Invalid/unknown slug 404, unregistered/wildcard Origin 403 |
| CORS/preflight | Exact registered Origin with credentials | Unsupported method/header and forged app declaration rejected |

## Quality Results

- `pnpm db:test`: PASS — 171 tests
- `pnpm rls:test`: PASS — 29 tests
- `pnpm functions:test`: PASS — 4 function shells
- `pnpm test:contract`: PASS — 6 tests
- `pnpm test:integration`: PASS — 11 tests
- `pnpm test:e2e --grep P1`: PASS — 3/3 headless tests
- `pnpm typecheck`, `pnpm lint`, `pnpm format:check`, `pnpm test`, and `pnpm build`: PASS

## Sensitive-Data Checks

The covered failure responses are checked for absence of raw session tokens, token/CSRF hashes, SQLSTATE, stack traces, and database implementation details. E2E failure artifacts are generated only on failure and the passing run produced no artifacts containing credentials.

## Deferred Boundary

`GET /v1/admin/session` is a P1 contract and acceptance dependency, but its implementation is assigned to P3-T002 (`docs/implementation/phases/03-admin-foundation.md`). P1-T013 therefore cannot be marked complete without either resolving the task ordering or moving the Admin Session implementation into P1. See `AB-001`.
