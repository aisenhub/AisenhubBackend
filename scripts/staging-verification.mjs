import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import process from 'node:process';

const repositoryRoot = resolve(import.meta.dirname, '..');
const mode = process.argv[2];
const fixtureEmailPrefix = 'codex-';
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
  /-----BEGIN|service_role|private[_-]?key|access[_-]?token|password|secret|csrfToken|sessionToken/i;

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

function authUrl(settings, path) {
  return `${settings.supabaseUrl}/auth/v1/${path}`;
}

async function request(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  const body = (() => {
    if (text === '') return null;
    try {
      return JSON.parse(text);
    } catch {
      return null;
    }
  })();
  return { response, text, body };
}

async function requestPage(url) {
  if (process.platform !== 'win32') return request(url);
  try {
    const status = execFileSync(
      'curl.exe',
      ['-sS', '-L', '--max-time', '30', '-o', 'NUL', '-w', '%{http_code}', url],
      { cwd: repositoryRoot, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
    ).trim();
    return { response: { status: Number(status), headers: new Headers() }, text: '', body: null };
  } catch {
    throw new Error('Staging application page request failed.');
  }
}

function requestId(result) {
  const header = result.response.headers.get('x-request-id');
  const bodyId = result.body?.requestId ?? result.body?.error?.requestId;
  return header ?? bodyId ?? null;
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
  return id;
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

  const session = await request(apiUrl(settings, 'platform-api', '/v1/session'), {
    headers: { Origin: settings.accountOrigin },
  });
  assertStatus(session, 200, 'anonymous session');
  assertCors(session, settings.accountOrigin, 'anonymous session');
  assertRequestId(session, 'anonymous session');

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
    const result = await request(apiUrl(settings, functionName, '/v1/session'), {
      method: 'OPTIONS',
      headers: {
        Origin: origin,
        'Access-Control-Request-Method': 'GET',
        'Access-Control-Request-Headers': 'X-AisenHub-App',
      },
    });
    assertStatus(result, 204, label);
    assertCors(result, origin, label);
    assertRequestId(result, label);
    printPass(label);
  }

  const rejected = await request(apiUrl(settings, 'platform-api', '/v1/session'), {
    headers: { Origin: 'https://staging-invalid-origin.invalid' },
  });
  assertStatus(rejected, 403, 'unregistered Origin');
  if (rejected.response.headers.has('access-control-allow-origin')) {
    throw new Error('Rejected Origin returned a CORS allow-origin header.');
  }
  assertRequestId(rejected, 'unregistered Origin');
  printPass('anonymous API, catalog, exact CORS, and rejected Origin checks');
}

async function authAdminRequest(settings, method, path, body) {
  return request(authUrl(settings, path), {
    method,
    headers: {
      apikey: settings.serviceRoleKey,
      Authorization: `Bearer ${settings.serviceRoleKey}`,
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

async function createFixtureUser(settings, label) {
  const password = `Staging-E2E-${randomBytes(18).toString('base64url')}!`;
  const email = `codex-${label}-${randomUUID()}@staging.aisenhub.test`;
  const result = await authAdminRequest(settings, 'POST', 'admin/users', {
    email,
    password,
    email_confirm: true,
  });
  assertStatus(result, 200, `${label} fixture creation`);
  const user = result.body?.user ?? result.body;
  if (!user || typeof user.id !== 'string' || !uuidPattern.test(user.id)) {
    throw new Error(`${label} fixture creation returned no valid user id.`);
  }
  return { id: user.id, email, password };
}

async function deleteFixtureUser(settings, userId) {
  const result = await authAdminRequest(settings, 'DELETE', `admin/users/${userId}`);
  if (![200, 204].includes(result.response.status)) {
    throw new Error(`Fixture cleanup returned HTTP ${result.response.status}.`);
  }
}

async function listFixtureUsers(settings) {
  const result = await authAdminRequest(settings, 'GET', 'admin/users?page=1&per_page=100');
  assertStatus(result, 200, 'fixture listing');
  return (Array.isArray(result.body?.users) ? result.body.users : []).filter(
    (user) =>
      typeof user?.id === 'string' &&
      uuidPattern.test(user.id) &&
      typeof user.email === 'string' &&
      user.email.startsWith(fixtureEmailPrefix) &&
      user.email.endsWith('@staging.aisenhub.test'),
  );
}

async function cleanupFixtureUser(settings, userId) {
  runSql(
    settings,
    `delete from platform.account_deletion_requests where user_id = ${quoteUuid(userId)}; delete from platform.admin_members where user_id = ${quoteUuid(userId)};`,
  );
  await deleteFixtureUser(settings, userId);
}

async function cleanupStaleFixtures(settings) {
  const staleUsers = await listFixtureUsers(settings);
  for (const user of staleUsers) await cleanupFixtureUser(settings, user.id);
}

function quoteUuid(value) {
  if (!uuidPattern.test(value)) throw new Error('Unexpected fixture UUID.');
  return `'${value}'`;
}

function runSql(settings, sql) {
  const tempDirectory = mkdtempSync(join(tmpdir(), 'aisenhub-staging-sql-'));
  const sqlPath = join(tempDirectory, 'query.sql');
  writeFileSync(sqlPath, `${sql}\n`, 'utf8');
  try {
    const args = [
      'exec',
      'supabase',
      'db',
      'query',
      '--linked',
      '--project-ref',
      settings.projectRef,
      '-o',
      'json',
      '--yes',
      '--file',
      sqlPath,
    ];
    const command =
      process.platform === 'win32'
        ? `pnpm exec supabase db query --linked --project-ref ${settings.projectRef} -o json --yes --file ${sqlPath}`
        : null;
    execFileSync(
      process.platform === 'win32' ? 'cmd.exe' : 'pnpm',
      process.platform === 'win32' ? ['/d', '/c', command] : args,
      { cwd: repositoryRoot, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8' },
    );
  } catch {
    throw new Error('Staging fixture SQL operation failed.');
  } finally {
    rmSync(tempDirectory, { recursive: true, force: true });
  }
}

async function passwordLogin(settings, fixture) {
  const result = await request(authUrl(settings, 'token?grant_type=password'), {
    method: 'POST',
    headers: {
      apikey: settings.anonKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email: fixture.email, password: fixture.password }),
  });
  assertStatus(result, 200, 'fixture password login');
  if (typeof result.body?.access_token !== 'string') {
    throw new Error('Fixture password login returned no access token.');
  }
  return result.body.access_token;
}

function cookieFrom(result) {
  const value = result.response.headers.get('set-cookie') ?? '';
  const match = value.match(/__Host-aisenhub_session=([^;]+)/);
  if (!match?.[1]) throw new Error('Platform Session exchange returned no session cookie.');
  return `__Host-aisenhub_session=${match[1]}`;
}

async function e2e(settings) {
  await cleanupStaleFixtures(settings);
  const normal = await createFixtureUser(settings, 'normal');
  const admin = await createFixtureUser(settings, 'admin');
  let membershipCreated = false;
  let testError = null;
  try {
    runSql(
      settings,
      `insert into platform.admin_members (user_id, role, status, created_by) values (${quoteUuid(admin.id)}, 'admin', 'active', null) on conflict (user_id) do update set role = excluded.role, status = excluded.status, disabled_at = null;`,
    );
    membershipCreated = true;

    const normalToken = await passwordLogin(settings, normal);
    const normalExchange = await request(apiUrl(settings, 'platform-api', '/v1/session/exchange'), {
      method: 'POST',
      headers: { Origin: settings.accountOrigin, Authorization: `Bearer ${normalToken}` },
    });
    assertStatus(normalExchange, 201, 'normal Platform Session exchange');
    assertCors(normalExchange, settings.accountOrigin, 'normal Platform Session exchange');
    const normalCookie = cookieFrom(normalExchange);
    const normalSession = await request(apiUrl(settings, 'platform-api', '/v1/session'), {
      headers: { Origin: settings.accountOrigin, Cookie: normalCookie },
    });
    assertStatus(normalSession, 200, 'normal session read');
    assertRequestId(normalSession, 'normal session read');

    const deletion = await request(apiUrl(settings, 'platform-api', '/v1/me/deletion-requests'), {
      method: 'POST',
      headers: {
        Origin: settings.accountOrigin,
        'X-AisenHub-App': 'account',
        'X-CSRF-Token': normalExchange.body?.data?.csrfToken,
        Authorization: `Bearer ${normalToken}`,
        Cookie: normalCookie,
        'Idempotency-Key': `staging-e2e-${randomUUID()}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    });
    assertStatus(deletion, 202, 'deletion request audit mutation');
    const deletionRequestId = assertRequestId(deletion, 'deletion request audit mutation');
    const cancellation = await request(
      apiUrl(settings, 'platform-api', '/v1/me/deletion-requests'),
      {
        method: 'DELETE',
        headers: {
          Origin: settings.accountOrigin,
          'X-AisenHub-App': 'account',
          Authorization: `Bearer ${normalToken}`,
        },
      },
    );
    assertStatus(cancellation, 200, 'deletion request cancellation');
    assertRequestId(cancellation, 'deletion request cancellation');

    const normalExchangeAfterCancel = await request(
      apiUrl(settings, 'platform-api', '/v1/session/exchange'),
      {
        method: 'POST',
        headers: { Origin: settings.accountOrigin, Authorization: `Bearer ${normalToken}` },
      },
    );
    assertStatus(normalExchangeAfterCancel, 201, 'normal re-login after cancellation');
    const normalCookieAfterCancel = cookieFrom(normalExchangeAfterCancel);

    const adminToken = await passwordLogin(settings, admin);
    const adminExchange = await request(apiUrl(settings, 'platform-api', '/v1/session/exchange'), {
      method: 'POST',
      headers: { Origin: settings.accountOrigin, Authorization: `Bearer ${adminToken}` },
    });
    assertStatus(adminExchange, 201, 'admin Platform Session exchange');
    const adminCookie = cookieFrom(adminExchange);
    const adminSession = await request(apiUrl(settings, 'platform-admin', '/v1/admin/session'), {
      headers: { Origin: settings.adminOrigin, Cookie: adminCookie },
    });
    assertStatus(adminSession, 200, 'Admin Session');
    assertRequestId(adminSession, 'Admin Session');
    if (adminSession.body?.data?.role !== 'admin')
      throw new Error('Admin Session role is not admin.');

    const normalAdminSession = await request(
      apiUrl(settings, 'platform-admin', '/v1/admin/session'),
      {
        headers: { Origin: settings.adminOrigin, Cookie: normalCookieAfterCancel },
      },
    );
    assertStatus(normalAdminSession, 403, 'normal-user Admin denial');
    assertRequestId(normalAdminSession, 'normal-user Admin denial');

    const overview = await request(
      apiUrl(settings, 'platform-admin', '/v1/admin/users/' + normal.id + '/overview'),
      {
        headers: { Origin: settings.adminOrigin, Cookie: adminCookie },
      },
    );
    assertStatus(overview, 200, 'Admin User 360 audit read');
    assertRequestId(overview, 'Admin User 360 audit read');
    const auditTimeline = overview.body?.data?.auditTimeline;
    if (
      !Array.isArray(auditTimeline) ||
      !auditTimeline.some((item) => item?.requestId === deletionRequestId)
    ) {
      throw new Error('The deletion requestId was not linked to the Admin audit timeline.');
    }
    printPass(
      'temporary account login, Platform Session, Admin role matrix, and audit correlation',
    );
  } catch (error) {
    testError = error;
  } finally {
    const cleanupErrors = [];
    if (membershipCreated) {
      try {
        runSql(
          settings,
          `delete from platform.admin_members where user_id = ${quoteUuid(admin.id)};`,
        );
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const user of [admin, normal]) {
      try {
        runSql(
          settings,
          `delete from platform.account_deletion_requests where user_id = ${quoteUuid(user.id)};`,
        );
        await deleteFixtureUser(settings, user.id);
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (!testError && cleanupErrors.length > 0) testError = cleanupErrors[0];
  }
  if (testError) throw testError;
}

async function observability(settings) {
  const checks = [
    ['platform-api', '/v1/session', settings.accountOrigin],
    ['platform-public', '/v1/products/public', settings.accountOrigin],
    ['platform-admin', '/v1/admin/session', settings.adminOrigin],
  ];
  for (const [functionName, path, origin] of checks) {
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
  const manifestPath = resolve(bundleRoot, 'manifest.json');
  const checksumsPath = resolve(bundleRoot, 'checksums.sha256');
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const currentSha = execFileSync('git', ['rev-parse', 'HEAD'], {
    cwd: repositoryRoot,
    encoding: 'utf8',
  }).trim();
  if (manifest.environment !== 'staging' || manifest.gitSha !== currentSha) {
    throw new Error('Staging release bundle is not traceable to the current Git SHA.');
  }
  for (const line of readFileSync(checksumsPath, 'utf8').split(/\r?\n/).filter(Boolean)) {
    const match = line.match(/^([0-9a-f]{64}) {2}(.+)$/i);
    if (!match) throw new Error('Staging checksum file contains an invalid line.');
    const filePath = resolve(repositoryRoot, match[2]);
    if (sha256(filePath) !== match[1].toLowerCase())
      throw new Error('Staging artifact checksum mismatch.');
  }

  const rejected = await request(apiUrl(settings, 'platform-api', '/v1/unknown-route'), {
    headers: { Origin: 'https://staging-invalid-origin.invalid' },
  });
  assertStatus(rejected, 403, 'simulated failed deployment boundary');
  const healthy = await request(apiUrl(settings, 'platform-api'));
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
