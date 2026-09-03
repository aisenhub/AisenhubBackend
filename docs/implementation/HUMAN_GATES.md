# AisenHub Breaking Rebuild — Human Gates

Local implementation budget: **0 routine interactions**.

## HG-001 — Provider / Cloud Authorization (conditional)

Trigger only when the Agent has already checked existing scoped access and cannot autonomously:

- enable/inspect Supabase OAuth Server;
- manage the required signing configuration;
- register Staging/Production OAuth clients;
- configure named cloud environment variables.

Ask once with a no-secret checklist. Never ask the user to paste secrets into chat.

This gate is skipped when existing access is sufficient.

## HG-002 — Destructive Production Rebuild / Deploy (mandatory)

Required before destructive change to a Production Supabase project or Production hosting, even if the project currently has no users.

Before asking, provide:

- exact target project/environment identity;
- exact migrations/artifact Git SHA;
- what existing Production state will be destroyed/replaced;
- backup/export decision;
- OAuth/signing/client configuration changes;
- smoke tests;
- stop conditions and recovery plan.

Approval applies only to the described scope.

## HG-003 — Public DNS / Real Payments / Commercial Go-live (conditional)

Required only when the user actually wants public traffic or real money.

Keep deferred while this is a technical platform rebuild.

Do not infer commercial promises, prices, refund policy, payment provider, or legal retention periods.
