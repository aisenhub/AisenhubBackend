# Local Environment Baseline

Last verified: 2026-09-01

## Repository

- Workspace: `E:\Projects\AisenHub-platform`
- Repository state at baseline: Git was not initialized when the task started; a local Git repository was initialized during P0-T001.
- Branch: `main`
- Remote: none configured
- Initial commit: not yet created at baseline capture
- Existing content: root and scoped agent rules, architecture documentation, implementation plan, and no business implementation.
- Cloud resources or credentials: not required or accessed.

## Host and toolchain

| Tool | Required baseline | Observed state | Remediation |
| --- | --- | --- | --- |
| Windows | Windows 10/11 compatible host | Windows 10 Home, build 19045 | N/A |
| Node.js | 24.19.0 | `v24.19.0` | N/A |
| pnpm | 11.24.0 | `11.24.0` | N/A |
| Git | 2.55.0 or compatible | `git version 2.55.0.windows.5` | N/A; repository initialized by P0-T001 |
| Docker Desktop | 4.88.1 | Not installed / daemon unavailable | Run `winget install --id Docker.DockerDesktop -e --accept-source-agreements --accept-package-agreements`, then start Docker Desktop and verify `docker version`. |
| Supabase CLI | 2.116.0 | Not installed globally | Use the pinned workspace CLI after P0-T002: `pnpm exec supabase --version`; fallback `pnpm dlx supabase@2.116.0 --version`. |
| Browser for E2E | Playwright-managed Chromium | No system browser executable detected | Install the workspace Playwright browser during the E2E/bootstrap task with the repository's pinned dependency command. |

## Detection evidence

```text
node --version       v24.19.0
pnpm --version       11.24.0
git --version        git version 2.55.0.windows.5
docker               command not found; Docker daemon check unavailable
supabase             command not found
```

The Docker Desktop installer was invoked through `winget`, but the package was not registered as installed during this baseline capture. This is a local prerequisite remediation item, not a cloud or production gate.

## Version pinning

The pinned versions are recorded in the repository-root `.tool-versions`. Workspace dependencies and scripts must use these versions or a compatible lockfile-resolved version; do not silently switch package managers or backend stacks.

## P0-T001 result

The repository, scoped instructions, local toolchain, missing prerequisites, and autonomous remediation paths are recorded. The next task is P0-T002.
