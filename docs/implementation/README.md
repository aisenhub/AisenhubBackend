# Breaking Rebuild Implementation

This directory contains the only active implementation plan for the Unified Identity Platform breaking rebuild.

## Execution order

```text
R0 -> R1 -> R2 -> R3 -> R4 -> R5
```

Read:

1. `../AISENHUB_UNIFIED_IDENTITY_PLATFORM_ARCHITECTURE_V2.md`
2. `MASTER_PLAN.md`
3. `AGENT_EXECUTION_RULES.md`
4. the current phase file
5. `HUMAN_GATES.md` only when a task explicitly reaches a gate

There is intentionally no `PROGRESS.md`, `TASK_LEDGER.md`, `checkpoints/`, or `reports/` directory. Git commits and automated test/CI evidence are the execution history.
