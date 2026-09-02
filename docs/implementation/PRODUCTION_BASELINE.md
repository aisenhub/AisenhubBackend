# Production Capability Baseline

Date: 2026-09-02  
Scope: read-only Production readiness inspection  
Status: human gate required  
Mutation: none

## Summary

Staging is complete and isolated. Supabase CLI authorization is available and
the account can see two healthy Supabase projects. The existing
`aisenhubProject` project is a separate healthy project and a possible
Production candidate, but its Production identity is not configured in the
protected environment and it is not linked as the current repository target.

Production is not deployable yet because the Production environment contract,
hosting origins, and formal DNS readiness are not available to the Agent.
Production migration, function deployment, secret changes, hosting changes,
and DNS changes were not attempted.

## Read-only evidence

Command:

```text
pnpm production:preflight --check-only --no-mutate
```

Additional verification:

```text
pnpm production:preflight:test
```

Result: passed. The test confirms that configured secret sentinels are absent
from preflight output and that a Supabase URL/project-ref mismatch is rejected
as not ready.

Observed results:

| Area | Result |
| --- | --- |
| Supabase CLI authorization | available |
| Visible Supabase projects | 2 |
| Separate project candidate | `aisenhubProject`, healthy, not linked |
| Production project ref variable | missing |
| Production Supabase URL variable | missing |
| Production secret/config variables | 9 of 9 missing |
| Production Account/Admin/API Origins | all missing |
| Vercel CLI | not available in the protected environment |
| `api.aisenhub.com` | unresolved |
| `account.aisenhub.com` | unresolved |
| `admin.aisenhub.com` | unresolved |
| Production state mutation | none |

The visible project candidate has ref `zyucbdhgtqxqnkjruvaf`; this is recorded
only as non-secret resource identity. It has not been assumed to be a live
Production database without the protected Production configuration and the
required authorization.

## Required protected variables

Presence was checked without printing values. Configure these names only in the
approved protected environment; never paste their values into chat or commit
them:

```text
PRODUCTION_SUPABASE_PROJECT_REF
PRODUCTION_SUPABASE_URL
PRODUCTION_SUPABASE_ANON_KEY
PRODUCTION_SUPABASE_SERVICE_ROLE_KEY
PRODUCTION_REDEMPTION_PEPPER
PRODUCTION_PAYMENT_WEBHOOK_SECRET
PRODUCTION_API_ORIGIN
PRODUCTION_ACCOUNT_ORIGIN
PRODUCTION_ADMIN_ORIGIN
```

`PRODUCTION_SUPABASE_SERVICE_ROLE_KEY`, `PRODUCTION_REDEMPTION_PEPPER`, and
`PRODUCTION_PAYMENT_WEBHOOK_SECRET` must be Production-only values. They must
not be copied from Local or Staging.

## Isolation review

- The configured Staging project remains `workendstaging`; no Production
  project was linked, migrated, reset, or deployed.
- Staging provider URLs are not treated as Production origins.
- No Production secret value was read into evidence or written to the
  repository.
- No Production database, Auth user, payment setting, hosting project, or DNS
  record was changed.

## HG-003 missing-item bundle

HG-003 is `ready`. Resolve these items together in one scoped interaction:

1. Confirm/authorize the dedicated Production Supabase project and its
   read-only discovery plus deployment scope. The existing
   `aisenhubProject` may be selected only after its Production role is
   explicitly confirmed.
2. Configure the nine named `PRODUCTION_*` variables in the protected
   environment, without disclosing values in chat.
3. Provide or authorize the Production hosting resources and their exact
   Account/Admin/API origins. Provider URLs may be used if custom DNS is not
   part of the first release.
4. Decide whether the canonical `*.aisenhub.com` DNS records are part of the
   first release. DNS/payment cutover remains a separate HG-005 decision.

This gate is infrastructure/configuration readiness only. It is not approval
to run Production migrations or deploy services; HG-004 remains mandatory.

Architecture Deviations: None.
