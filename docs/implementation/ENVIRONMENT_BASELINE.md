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
| Docker Desktop | 4.88.1 | Installed at `D:\APP\Base\DockerDesktop`; daemon currently blocked by outdated WSL | Update WSL using the Windows system update mechanism, then start Docker Desktop and verify `docker version`. |
| WSL | In-box Windows 10 WSL | Installed but too old for Docker Desktop | `wsl --update` is required; the command has no custom installation-directory option and therefore needs explicit handling under the repository install-path rule. |
| Supabase CLI | 2.116.0 | Workspace CLI verified as `2.116.0`; not installed globally | Use `pnpm exec supabase --version`. |
| Browser for E2E | Playwright-managed Chromium | No system browser executable detected | Install the workspace Playwright browser during the E2E/bootstrap task with the repository's pinned dependency command. |

## Detection evidence

```text
node --version       v24.19.0
pnpm --version       11.24.0
git --version        git version 2.55.0.windows.5
docker               29.7.2 client installed at `D:\APP\Base\DockerDesktop\resources\bin`; Linux daemon unavailable because WSL is too old
supabase             workspace CLI `2.116.0` via `pnpm exec supabase --version`
```

Docker Desktop 4.88.1 was subsequently installed successfully with administrative elevation at `D:\APP\Base\DockerDesktop`; its registered uninstall path also points there. The installer enabled `VirtualMachinePlatform` and `Microsoft-Windows-Subsystem-Linux`. Docker now reports that the installed WSL version is too old. The WSL update command has no custom installation-directory option, so it is paused under the repository's explicit install-path rule. This is a local prerequisite remediation item, not a cloud or production gate.

P0-T004 also attempted the cached Docker Desktop installer and the cached Podman installer directly. Docker Desktop is now installed under `D:\APP\Base\DockerDesktop`, while `pnpm supabase:start` remains a reproducible failed check until WSL is updated. The failed first installation is retained in `D:\APP\Base\_DockerDesktop_failed_install_20260901` for recovery and does not contain the other tools in `D:\APP\Base`.

## Version pinning

The pinned versions are recorded in the repository-root `.tool-versions`. Workspace dependencies and scripts must use these versions or a compatible lockfile-resolved version; do not silently switch package managers or backend stacks.

## P0-T001 result

The repository, scoped instructions, local toolchain, missing prerequisites, and autonomous remediation paths are recorded. The next task is P0-T002.
