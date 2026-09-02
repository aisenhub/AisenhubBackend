import { defineConfig, devices } from '@playwright/test';
import { execFileSync } from 'node:child_process';

function localAnonKey(): string {
  if (process.env.VITE_SUPABASE_ANON_KEY) return process.env.VITE_SUPABASE_ANON_KEY;

  const pathValue = `D:\\APP\\Base\\DockerDesktop\\resources\\bin;${process.env.Path ?? ''}`;
  const output = execFileSync(
    process.env.ComSpec ?? 'cmd.exe',
    ['/d', '/s', '/c', 'pnpm exec supabase status --output env'],
    {
      cwd: process.cwd(),
      encoding: 'utf8',
      env: { ...process.env, Path: pathValue },
      stdio: ['ignore', 'pipe', 'ignore'],
    },
  );
  const match = output.match(/^ANON_KEY="?([^"\r\n]+)"?$/m);
  if (!match) throw new Error('Local Supabase anon key is unavailable for Account E2E.');
  return match[1];
}

const localSupabaseAnonKey = localAnonKey();
const accountBaseUrl = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:5173';
const accountPort = new URL(accountBaseUrl).port || '5173';
const adminBaseUrl = process.env.PLAYWRIGHT_ADMIN_BASE_URL ?? 'http://localhost:5174';
const adminPort = new URL(adminBaseUrl).port || '5174';

const webServerEnv = {
  ...process.env,
  Path: `D:\\APP\\Base\\DockerDesktop\\resources\\bin;${process.env.Path ?? ''}`,
  VITE_SUPABASE_ANON_KEY: localSupabaseAnonKey,
  E2E_PROXY_TARGET: 'http://127.0.0.1:54321',
  E2E_PROXY_ORIGIN: 'http://localhost:5173',
  VITE_PLATFORM_API_URL: '/functions/v1/platform-api',
  VITE_PLATFORM_PUBLIC_API_URL: '/functions/v1/platform-public',
  REDEMPTION_PEPPER: 'local-e2e-only-pepper',
  REDEMPTION_PEPPER_VERSION: '1',
};
const adminWebServerEnv = {
  ...webServerEnv,
  // The local database fixture registers the canonical Admin origin on 5174.
  // Keep the backend Origin stable when the browser uses an alternate port to avoid collisions.
  E2E_PROXY_ORIGIN: 'http://localhost:5174',
  VITE_PLATFORM_ADMIN_API_ORIGIN: '/functions/v1/platform-admin',
  VITE_PLATFORM_API_ORIGIN: '/functions/v1/platform-api',
  VITE_ACCOUNT_ORIGIN: 'http://localhost:5173',
};

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  reporter: [['list']],
  use: {
    baseURL: accountBaseUrl,
    trace: 'on-first-retry',
  },
  webServer: [
    {
      command: 'pnpm exec supabase functions serve platform-api platform-public --no-verify-jwt',
      url: `http://127.0.0.1:54321/functions/v1/platform-api/v1/session?apikey=${localSupabaseAnonKey}`,
      timeout: 120_000,
      reuseExistingServer: true,
      env: webServerEnv,
    },
    {
      command: `pnpm --dir apps/account dev --host 0.0.0.0 --port ${accountPort}`,
      url: accountBaseUrl,
      timeout: 120_000,
      reuseExistingServer: !process.env.CI,
      env: webServerEnv,
    },
    {
      command: `pnpm --dir apps/admin dev --host 0.0.0.0 --port ${adminPort}`,
      url: adminBaseUrl,
      timeout: 120_000,
      reuseExistingServer: !process.env.CI,
      env: adminWebServerEnv,
    },
  ],
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
