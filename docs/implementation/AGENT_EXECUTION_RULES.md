# AisenHub Breaking Rebuild — Agent Execution Rules

## 1. Authority

Read in this order:

1. `docs/AISENHUB_UNIFIED_IDENTITY_PLATFORM_ARCHITECTURE_V2.md`
2. `docs/implementation/MASTER_PLAN.md`
3. current `docs/implementation/phases/*.md`
4. root/scoped `AGENTS.md`
5. current source code

If implementation cannot satisfy the architecture safely, stop that task and surface an `ARCHITECTURE_BLOCKER`; do not create a hidden compatibility workaround.

## 2. No compatibility preservation

This rebuild has no real users/production data/external consumers to protect.

Therefore an Agent must **not** preserve old behavior merely because:

- an old test expects it;
- an archived plan described it;
- `/v1` already exists in source;
- old fixtures depend on it;
- deleting it causes a large diff.

Old tests/contracts/fixtures that encode obsolete Platform Session or Origin-auth behavior must be rewritten or removed.

## 3. What must be preserved

Preserve proven business/security invariants unless the new architecture explicitly changes them:

- atomic Commerce/Redemption/Entitlement operations;
- idempotency;
- audit reliability;
- RLS / private schema boundaries;
- fixed `search_path` on privileged functions;
- Admin backend authorization / MFA;
- client-to-API contract boundary;
- secret redaction.

## 4. Autonomous First

Local work is autonomous. Do not ask the user to:

- inspect files;
- run tests;
- create Local fixtures;
- approve routine refactors;
- decide implementation details already fixed by architecture.

Only stop for an explicit Human Gate or a genuine architecture contradiction.

## 5. Destructive work

Allowed without extra approval when the active task requires it:

- Local database reset;
- Local fixture replacement;
- deletion of obsolete code/tests/docs;
- migration rewrite/squash after the preconditions in R4 are met;
- Staging reset when target identity is verified and Staging contains no required data.

Always require explicit approval before destructive Production reset/deploy.

## 6. Documentation discipline

Do not create:

- per-task reports;
- checkpoints;
- progress diaries;
- task ledgers with timestamps/commits;
- temporary environment baselines inside `docs/`.

Execution history belongs in Git and CI.

A new long-lived Markdown file needs a clear stable purpose under the docs policy.

## 7. Task completion

For each task:

1. read dependencies and acceptance criteria;
2. inspect current code/tests;
3. write the failing/guard tests where appropriate;
4. implement the smallest complete architecture-correct change;
5. run narrow tests first;
6. run all affected quality gates;
7. commit with the task ID;
8. continue to the next dependency-ready task.

Do not update a progress document; the commit history and passing acceptance checks are the record.

## 8. Required quality commands

Use applicable existing scripts:

```bash
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm db:reset
pnpm db:test
pnpm rls:test
pnpm test:contract
pnpm test:integration
pnpm test:security
pnpm test:e2e
pnpm boundaries:check
pnpm secrets:check
pnpm platform:verify
```

Phase gates run the full applicable set, not just targeted tests.
