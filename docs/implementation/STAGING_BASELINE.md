# Staging Capability Baseline

中文说明：[`STAGING_BASELINE.zh-CN.md`](STAGING_BASELINE.zh-CN.md)

Date: 2026-09-02
Status: HG-001 ready
Environment inspected: Staging only; no remote resource was changed

## Update after user setup

The user authorized the Supabase CLI and created an isolated Staging project.
The accessible project is `workendstaging`, Ref
`egsokuicabbxspkdccqe`, URL
`https://egsokuicabbxspkdccqe.supabase.co`, and status
`ACTIVE_HEALTHY`. Hosting/DNS and named Staging variables are still not
configured in the Codex environment.

The user has since supplied healthy Vercel provider URLs for Account and
Admin. Custom DNS is not required for the initial Staging smoke tests.
The non-secret project/origin values are present in the Windows user
environment; the already-running Codex process must be restarted before it
can inherit those newly written values.

The two Vercel pages return HTTP 200, but their current bundles still contain
Local default hosts (`localhost`/`127.0.0.1`). Their Vercel build variables
must be configured and the deployments must be rebuilt before Staging smoke
tests.

## Discovery result

The safe discovery command was:

```bash
pnpm exec supabase projects list
pnpm staging:preflight --check-only
```

Supabase project discovery returned an authentication-required result: no
usable saved Supabase CLI login or access-token environment variable is
available in the current environment. The preflight checker invokes the CLI
so either `supabase login` state or `SUPABASE_ACCESS_TOKEN` is accepted; it
reports only capability names and booleans and never prints environment
values.

| Capability | Result | Evidence |
| --- | --- | --- |
| Supabase CLI authentication | Available | Saved CLI login now allows project discovery |
| Staging Supabase project/ref | Available | `workendstaging` / `egsokuicabbxspkdccqe` is `ACTIVE_HEALTHY` |
| Staging hosting provider | Vercel provider URLs available | Account and Admin URLs both return HTTP 200 |
| Staging DNS/provider URL | Provider URLs | Custom DNS is not required for the initial smoke tests |
| Named Staging variables | Missing | `pnpm staging:preflight --check-only` reports presence only; no values were present |

Required names are defined in `scripts/staging-preflight.mjs`, including the
Staging project ref, URL, anon/service-role variables, redemption/payment
secrets, and API/Account/Admin origins. Values must be placed in the approved
secret/environment manager and must not be pasted into chat or committed.

## HG-001 consolidated bundle

HG-001 is ready for one consolidated interaction covering:

1. authorize the Supabase CLI and provide/authorize the isolated Staging
   project;
2. authorize the selected hosting path or provide the provider URL;
3. configure the named Staging variables in the designated manager; and
4. provide or approve temporary Staging API, Account, and Admin origins if DNS
   is required for the cross-origin smoke test.

No individual secret values are requested here. If an existing authorized
project, provider URL, and complete named configuration become available,
HG-001 can be skipped by re-running the same preflight and recording the
evidence.

## Independent continuation

Local work remains complete and P7-T002 can build the immutable, no-secret
Staging deployment bundle offline:

```bash
pnpm staging:preflight --offline
```

Staging deployment, migrations, secrets, DNS, and smoke tests remain gated and
are not inferred from this capability inspection.

Architecture Deviations: None
