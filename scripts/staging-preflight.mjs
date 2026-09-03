import { spawnSync } from 'node:child_process';
import process from 'node:process';

const checkOnly = process.argv.includes('--check-only');
const offline = process.argv.includes('--offline');
const requiredStagingVariables = [
  'STAGING_SUPABASE_PROJECT_REF',
  'STAGING_SUPABASE_URL',
  'STAGING_SUPABASE_ANON_KEY',
  'STAGING_SUPABASE_SERVICE_ROLE_KEY',
  'STAGING_REDEMPTION_PEPPER',
  'STAGING_PAYMENT_WEBHOOK_SECRET',
  'STAGING_ACCOUNT_OAUTH_CLIENT_ID',
  'STAGING_ADMIN_OAUTH_CLIENT_ID',
  'STAGING_API_ORIGIN',
  'STAGING_ACCOUNT_ORIGIN',
  'STAGING_ADMIN_ORIGIN',
];

function present(name) {
  return typeof process.env[name] === 'string' && process.env[name].trim() !== '';
}

function inspectSupabaseAuth() {
  if (offline) return 'not_checked_offline';
  const result = spawnSync(
    process.platform === 'win32' ? (process.env.ComSpec ?? 'cmd.exe') : 'pnpm',
    process.platform === 'win32'
      ? ['/d', '/s', '/c', 'pnpm exec supabase projects list']
      : ['exec', 'supabase', 'projects', 'list'],
    { cwd: process.cwd(), encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], shell: false },
  );
  if (result.status === 0) return 'available';
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  if (/access token|supabase login|not logged in/i.test(output)) return 'missing_auth';
  return 'unavailable';
}

function inspectHostingProvider() {
  const origins = ['STAGING_ACCOUNT_ORIGIN', 'STAGING_ADMIN_ORIGIN'];
  if (!origins.every(present)) return 'unconfigured';
  try {
    const hosts = origins.map((name) => new URL(process.env[name]).hostname);
    if (hosts.every((host) => host.endsWith('.vercel.app'))) return 'vercel';
    return 'configured';
  } catch {
    return 'invalid_origin';
  }
}

function inspectStagingDns(hostingProvider) {
  if (hostingProvider === 'vercel') return 'provider_urls';
  if (hostingProvider === 'configured') return 'configured';
  return 'unconfigured';
}

const hostingProvider = inspectHostingProvider();
const checks = {
  supabaseCliAuth: inspectSupabaseAuth(),
  hostingProvider,
  stagingDns: inspectStagingDns(hostingProvider),
  variables: Object.fromEntries(requiredStagingVariables.map((name) => [name, present(name)])),
};

console.log(
  JSON.stringify(
    { mode: offline ? 'offline' : checkOnly ? 'check-only' : 'default', checks },
    null,
    2,
  ),
);

if (!checkOnly && !offline) {
  const missing = requiredStagingVariables.filter((name) => !checks.variables[name]);
  if (checks.supabaseCliAuth !== 'available' || missing.length > 0) process.exitCode = 1;
}
