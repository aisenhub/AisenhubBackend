# AisenHub Platform Documentation

> Snapshot basis: `main` @ `897eee2edb4010e3d049dbb851edaf944c8d0313` (2026-09-03)

## Current authority

1. [Unified Identity Platform Architecture V2](./AISENHUB_UNIFIED_IDENTITY_PLATFORM_ARCHITECTURE_V2.md)
2. [Breaking Rebuild Master Plan](./implementation/MASTER_PLAN.md)
3. [Agent Execution Rules](./implementation/AGENT_EXECUTION_RULES.md)
4. Current phase task file under `implementation/phases/`

## Core decision

This repository currently has no real production users/data or external clients that require compatibility. The active plan therefore performs a **breaking rebuild** of authentication/user management and does not maintain the former Platform Cookie Session architecture in parallel.

## Archive

`archive/` is deliberately curated. It preserves superseded **design and plan context**, plus exact source paths/SHAs for recovery from Git history.

It intentionally does **not** preserve routine process records such as progress logs, checkpoints, reports, temporary blockers, or one-off environment baselines.

## Documentation rule

If a Markdown file does not define architecture, the current plan, stable execution/operations rules, or a historically important superseded design, it normally does not belong in `docs/`.
