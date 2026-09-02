import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import process from 'node:process';

const secretSentinel = 'production-secret-sentinel-must-not-leak';

function run(extraEnvironment) {
  const result = spawnSync(
    process.execPath,
    ['scripts/production-preflight.mjs', '--check-only', '--no-mutate'],
    {
      cwd: process.cwd(),
      encoding: 'utf8',
      env: { ...process.env, ...extraEnvironment },
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(`${result.stdout}\n${result.stderr}`, new RegExp(secretSentinel));
  return JSON.parse(result.stdout);
}

const missing = run({
  PRODUCTION_SUPABASE_PROJECT_REF: '',
  PRODUCTION_SUPABASE_URL: '',
  PRODUCTION_SUPABASE_SERVICE_ROLE_KEY: secretSentinel,
});
assert.equal(missing.readiness, 'human_gate_required');
assert.equal(missing.supabase.environmentIdentity.url, 'not_configured');

const mismatched = run({
  PRODUCTION_SUPABASE_PROJECT_REF: 'production-ref-test',
  PRODUCTION_SUPABASE_URL: 'https://different-ref-test.supabase.co',
  PRODUCTION_SUPABASE_ANON_KEY: secretSentinel,
  PRODUCTION_SUPABASE_SERVICE_ROLE_KEY: secretSentinel,
  PRODUCTION_REDEMPTION_PEPPER: secretSentinel,
  PRODUCTION_PAYMENT_WEBHOOK_SECRET: secretSentinel,
  PRODUCTION_API_ORIGIN: 'https://api.example.test',
  PRODUCTION_ACCOUNT_ORIGIN: 'https://account.example.test',
  PRODUCTION_ADMIN_ORIGIN: 'https://admin.example.test',
});
assert.equal(mismatched.supabase.environmentIdentity.url, 'mismatch');
assert.equal(mismatched.readiness, 'human_gate_required');

console.log('Production preflight redaction and identity checks passed.');
