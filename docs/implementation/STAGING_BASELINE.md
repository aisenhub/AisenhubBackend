# Staging Capability Baseline

Date: 2026-09-02
Status: HG-001 ready
Environment inspected: Staging only; no remote resource was changed

## Discovery result

The safe discovery command was:

```bash
pnpm exec supabase projects list
pnpm staging:preflight --check-only
```

Supabase project discovery returned an authentication-required result: no
Supabase CLI access token is available in the current environment. The
preflight checker reports only capability names and booleans; it never prints
environment values.

| Capability | Result | Evidence |
| --- | --- | --- |
| Supabase CLI authentication | Missing | `projects list` requires `supabase login` or an access-token environment variable |
| Staging Supabase project/ref | Missing | No usable Staging project was discoverable |
| Staging hosting provider | Unconfigured | No selected existing Vercel/Cloudflare/other deployment config in this repository |
| Staging DNS/provider URL | Unconfigured | No existing Staging API/Account/Admin origins were available |
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
