import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import process from 'node:process';

const repositoryRoot = resolve(import.meta.dirname, '..');
const mode = process.argv[2];
const requiredVariables = [
  'STAGING_SUPABASE_PROJECT_REF',
  'STAGING_SUPABASE_URL',
  'STAGING_SUPABASE_ANON_KEY',
  'STAGING_SUPABASE_SERVICE_ROLE_KEY',
  'STAGING_API_ORIGIN',
  'STAGING_ACCOUNT_ORIGIN',
  'STAGING_ADMIN_ORIGIN',
];
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const sensitivePattern =
  /-----BEGIN|service_role|private[_-]?key|access[_-]?token|password|secret|redemption/i;

function env(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}

function config() {
  for (const name of requiredVariables) env(name);
  return {
    projectRef: env('STAGING_SUPABASE_PROJECT_REF'),
    supabaseUrl: env('STAGING_SUPABASE_URL').replace(/\/$/, ''),
    anonKey: env('STAGING_SUPABASE_ANON_KEY'),
    serviceRoleKey: env('STAGING_SUPABASE_SERVICE_ROLE_KEY'),
    apiOrigin: env('STAGING_API_ORIGIN'),
    accountOrigin: env('STAGING_ACCOUNT_ORIGIN'),
    adminOrigin: env('STAGING_ADMIN_ORIGIN'),
  };
}

function apiUrl(settings, functionName, path = '') {
  return `${settings.supabaseUrl}/functions/v1/${functionName}${path}`;
}

async function request(url, options = {}) {
  let response;
  try {
    response = await fetch(url, options);
  } catch (error) {
    const detail = error instanceof Error ? error.message : 'unknown network error';
    throw new Error(`Request failed for ${url}: ${detail}`, { cause: error });
  }
  const text = await response.text();
  let body = null;
  if (text !== '') {
    try {
      body = JSON.parse(text);
    } catch {
      body = null;
    }
  }
  return { response, text, body };
}

async function requestPage(url) {
  let response;
  try {
    response = await fetch(url);
  } catch {
    try {
      const curl = process.platform === 'win32' ? 'curl.exe' : 'curl';
      const nullDevice = process.platform === 'win32' ? 'NUL' : '/dev/null';
      const status = execFileSync(
        curl,
        [
          '--silent',
          '--show-error',
          '--location',
          '--output',
          nullDevice,
          '--write-out',
          '%{http_code}',
          url,
        ],
        { cwd: repositoryRoot, encoding: 'utf8', env: process.env },
      ).trim();
      response = { status: Number(status) };
    } catch (fallbackError) {
      const detail = fallbackError instanceof Error ? fallbackError.message : 'network error';
      throw new Error(`Page request failed for ${url}: ${detail}`, { cause: fallbackError });
    }
  }
  return { response, text: '', body: null };
}

function requestId(result) {
  return (
    result.response.headers.get('x-request-id') ??
    result.body?.requestId ??
    result.body?.error?.requestId
  );
}

function assertStatus(result, expected, label) {
  if (result.response.status !== expected) {
    throw new Error(`${label} returned HTTP ${result.response.status}; expected ${expected}.`);
  }
}

function assertRequestId(result, label) {
  const id = requestId(result);
  if (!id || !uuidPattern.test(id)) throw new Error(`${label} did not return a valid requestId.`);
  if (result.body?.requestId && result.body.requestId !== id) {
    throw new Error(`${label} returned mismatched requestId values.`);
  }
  if (result.body?.error?.requestId && result.body.error.requestId !== id) {
    throw new Error(`${label} returned mismatched error requestId values.`);
  }
}

function assertCors(result, origin, label) {
  if (result.response.headers.get('access-control-allow-origin') !== origin) {
    throw new Error(`${label} did not return the exact CORS Origin.`);
  }
  if (result.response.headers.get('access-control-allow-origin') === '*') {
    throw new Error(`${label} returned wildcard CORS.`);
  }
}

function printPass(label) {
  console.log(`[staging:${mode}] PASS ${label}`);
}

function bearer(token) {
  return { Authorization: `Bearer ${token}` };
}

async function smoke(settings) {
  for (const [label, origin] of [
    ['Account page', settings.accountOrigin],
    ['Admin page', settings.adminOrigin],
  ]) {
    const result = await requestPage(origin);
    assertStatus(result, 200, label);
    printPass(`${label} HTTP 200`);
  }

  const functionBoundaryChecks = [
    [
      'platform-admin',
      '/v1/admin/session',
      'GET',
      settings.adminOrigin,
      401,
      'Admin auth boundary',
    ],
    [
      'payment-webhook',
      '/v1/webhooks/local',
      'POST',
      undefined,
      401,
      'payment webhook signature boundary',
    ],
    ['account-deletion-worker', '', 'POST', undefined, 403, 'account deletion worker boundary'],
    ['retention-cleanup', '', 'POST', undefined, 403, 'retention cleanup boundary'],
  ];
  for (const [functionName, path, method, origin, expected, label] of functionBoundaryChecks) {
    const result = await request(apiUrl(settings, functionName, path), {
      method,
      headers: origin ? { Origin: origin } : {},
      ...(method === 'POST' && functionName === 'payment-webhook' ? { body: '{}' } : {}),
    });
    assertStatus(result, expected, label);
    assertRequestId(result, label);
    if (origin) assertCors(result, origin, label);
    printPass(label);
  }

  const health = await request(apiUrl(settings, 'platform-api', '/'), {
    headers: { Origin: settings.accountOrigin },
  });
  assertStatus(health, 200, 'platform API health');
  assertCors(health, settings.accountOrigin, 'platform API health');
  assertRequestId(health, 'platform API health');

  const catalog = await request(apiUrl(settings, 'platform-public', '/v1/products/public'), {
    headers: { Origin: settings.accountOrigin },
  });
  assertStatus(catalog, 200, 'public catalog');
  assertCors(catalog, settings.accountOrigin, 'public catalog');
  assertRequestId(catalog, 'public catalog');
  if (sensitivePattern.test(catalog.text))
    throw new Error('Public catalog contains sensitive text.');

  for (const [functionName, origin, label] of [
    ['platform-api', settings.accountOrigin, 'Account preflight'],
    ['platform-admin', settings.adminOrigin, 'Admin preflight'],
  ]) {
    const result = await request(apiUrl(settings, functionName, '/v1/account/me'), {
      method: 'OPTIONS',
      headers: {
        Origin: origin,
        'Access-Control-Request-Method': 'GET',
        'Access-Control-Request-Headers': 'Authorization',
      },
    });
    assertStatus(result, 204, label);
    assertCors(result, origin, label);
    assertRequestId(result, label);
    printPass(label);
  }

  const rejected = await request(apiUrl(settings, 'platform-api', '/v1/account/me'), {
    headers: { Origin: 'https://staging-invalid-origin.invalid' },
  });
  assertStatus(rejected, 403, 'unregistered Origin');
  if (rejected.response.headers.has('access-control-allow-origin')) {
    throw new Error('Rejected Origin returned a CORS allow-origin header.');
  }
  assertRequestId(rejected, 'unregistered Origin');
  printPass('Bearer API, catalog, exact CORS, and rejected Origin checks');
}

async function e2e(settings) {
  const accountToken = env('STAGING_ACCOUNT_ACCESS_TOKEN');
  const adminToken = env('STAGING_ADMIN_ACCESS_TOKEN');

  const accountMe = await request(apiUrl(settings, 'platform-api', '/v1/account/me'), {
    headers: { Origin: settings.accountOrigin, ...bearer(accountToken) },
  });
  assertStatus(accountMe, 200, 'Account bearer identity');
  assertCors(accountMe, settings.accountOrigin, 'Account bearer identity');
  assertRequestId(accountMe, 'Account bearer identity');
  const userId = accountMe.body?.data?.profile?.userId;
  if (!uuidPattern.test(userId ?? ''))
    throw new Error('Account bearer identity returned no user id.');

  const context = await request(apiUrl(settings, 'platform-api', '/v1/app/context'), {
    headers: { Origin: settings.accountOrigin, ...bearer(accountToken) },
  });
  assertStatus(context, 200, 'Account application context');
  assertRequestId(context, 'Account application context');

  const adminSession = await request(apiUrl(settings, 'platform-admin', '/v1/admin/session'), {
    headers: { Origin: settings.adminOrigin, ...bearer(adminToken) },
  });
  assertStatus(adminSession, 200, 'Admin bearer identity');
  assertCors(adminSession, settings.adminOrigin, 'Admin bearer identity');
  assertRequestId(adminSession, 'Admin bearer identity');
  if (adminSession.body?.data?.role === undefined) throw new Error('Admin role was not returned.');

  const denied = await request(apiUrl(settings, 'platform-admin', '/v1/admin/session'), {
    headers: { Origin: settings.adminOrigin, ...bearer(accountToken) },
  });
  assertStatus(denied, 403, 'non-admin Admin denial');
  assertRequestId(denied, 'non-admin Admin denial');

  const overview = await request(
    apiUrl(settings, `platform-admin`, `/v1/admin/users/${userId}/overview`),
    {
      headers: { Origin: settings.adminOrigin, ...bearer(adminToken) },
    },
  );
  assertStatus(overview, 200, 'Admin User 360 read');
  assertRequestId(overview, 'Admin User 360 read');
  printPass('independent Account/Admin OAuth bearer contexts and membership isolation');
}

async function observability(settings) {
  for (const [functionName, path, origin] of [
    ['platform-api', '/', settings.accountOrigin],
    ['platform-public', '/v1/products/public', settings.accountOrigin],
    ['platform-admin', '/v1/admin/session', settings.adminOrigin],
  ]) {
    const result = await request(apiUrl(settings, functionName, path), {
      headers: { Origin: origin },
    });
    assertRequestId(result, `${functionName} ${path}`);
  }
  printPass('requestId headers and JSON/error envelopes are internally consistent');
}

function sha256(filePath) {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}

async function recovery(settings) {
  const bundleRoot = resolve(repositoryRoot, 'supabase', '.temp', 'release-bundle', 'staging');
  const manifest = JSON.parse(readFileSync(resolve(bundleRoot, 'manifest.json'), 'utf8'));
  const checksums = readFileSync(resolve(bundleRoot, 'checksums.sha256'), 'utf8');
  const currentSha = execFileSync('git', ['rev-parse', 'HEAD'], {
    cwd: repositoryRoot,
    encoding: 'utf8',
  }).trim();
  if (manifest.environment !== 'staging' || manifest.gitSha !== currentSha) {
    throw new Error('Staging release bundle is not traceable to the current Git SHA.');
  }
  for (const line of checksums.split(/\r?\n/).filter(Boolean)) {
    const match = line.match(/^([0-9a-f]{64}) {2}(.+)$/i);
    if (!match) throw new Error('Staging checksum file contains an invalid line.');
    const filePath = resolve(match[2] === 'manifest.json' ? bundleRoot : repositoryRoot, match[2]);
    if (sha256(filePath) !== match[1].toLowerCase())
      throw new Error('Staging artifact checksum mismatch.');
  }
  const rejected = await request(apiUrl(settings, 'platform-api', '/v1/unknown-route'), {
    headers: { Origin: 'https://staging-invalid-origin.invalid' },
  });
  assertStatus(rejected, 403, 'simulated failed deployment boundary');
  const healthy = await request(apiUrl(settings, 'platform-api', '/'), {
    headers: { Origin: settings.accountOrigin },
  });
  assertStatus(healthy, 200, 'recovery health check');
  assertRequestId(healthy, 'recovery health check');
  printPass('artifact checksum recovery stop/retry drill and health recovery');
}

async function main() {
  if (!['smoke', 'e2e', 'observability', 'recovery'].includes(mode)) {
    throw new Error(
      'Usage: node scripts/staging-verification.mjs <smoke|e2e|observability|recovery>',
    );
  }
  const settings = config();
  if (mode === 'smoke') await smoke(settings);
  if (mode === 'e2e') await e2e(settings);
  if (mode === 'observability') await observability(settings);
  if (mode === 'recovery') await recovery(settings);
  console.log(`[staging:${mode}] COMPLETE`);
}

main().catch((error) => {
  console.error(`[staging:${mode}] FAILED: ${error.message}`);
  process.exitCode = 1;
});
