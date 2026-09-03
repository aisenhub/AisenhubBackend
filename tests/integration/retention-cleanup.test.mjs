import { afterAll, afterEach, describe, expect, it, vi } from 'vitest';

const serviceRoleKey = 'local-service-role-key';
const calls = [];
let rpcStatus = 200;
let cleanupResult = {
  dryRun: false,
  redemptionIpHashCount: 2,
  auditIpHashCount: 2,
  idempotencyResponseCount: 1,
  idempotencyDeletedCount: 1,
  batchSize: 100,
};
const config = {
  PLATFORM_RUNTIME_ENVIRONMENT: 'local',
  PLATFORM_CLEANUP_SECURITY_CONTEXT_RETENTION_SECONDS: '2592000',
  PLATFORM_CLEANUP_IDEMPOTENCY_RESPONSE_RETENTION_SECONDS: '0',
  PLATFORM_CLEANUP_BATCH_SIZE: '100',
  PLATFORM_CLEANUP_DRY_RUN: 'false',
};

vi.stubGlobal('Deno', {
  env: {
    get(name) {
      return {
        SUPABASE_URL: 'http://local.supabase',
        SUPABASE_ANON_KEY: 'local-anon-key',
        SUPABASE_SERVICE_ROLE_KEY: serviceRoleKey,
        ...config,
      }[name];
    },
  },
});
vi.stubGlobal(
  'fetch',
  vi.fn(async (url, init) => {
    calls.push({ url: String(url), body: JSON.parse(init.body) });
    if (rpcStatus !== 200) return new Response('{}', { status: rpcStatus });
    return new Response(JSON.stringify([cleanupResult]), {
      headers: { 'content-type': 'application/json' },
    });
  }),
);

const { handleRetentionCleanup } =
  await import('../../supabase/functions/retention-cleanup/index.ts');

function workerRequest(headers = {}) {
  return new Request('http://local.supabase/functions/v1/retention-cleanup', {
    method: 'POST',
    headers: { authorization: `Bearer ${serviceRoleKey}`, ...headers },
  });
}

afterAll(() => vi.unstubAllGlobals());

afterEach(() => {
  calls.length = 0;
  rpcStatus = 200;
  cleanupResult = {
    dryRun: false,
    redemptionIpHashCount: 2,
    auditIpHashCount: 2,
    idempotencyResponseCount: 1,
    idempotencyDeletedCount: 1,
    batchSize: 100,
  };
  Object.assign(config, {
    PLATFORM_RUNTIME_ENVIRONMENT: 'local',
    PLATFORM_CLEANUP_SECURITY_CONTEXT_RETENTION_SECONDS: '2592000',
    PLATFORM_CLEANUP_IDEMPOTENCY_RESPONSE_RETENTION_SECONDS: '0',
    PLATFORM_CLEANUP_BATCH_SIZE: '100',
    PLATFORM_CLEANUP_DRY_RUN: 'false',
  });
});

describe('retention cleanup worker', () => {
  it('sends bounded, server-configured cutoffs to the cleanup RPC', async () => {
    const response = await handleRetentionCleanup(workerRequest());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.cleanup).toMatchObject({
      dryRun: false,
      idempotencyDeletedCount: 1,
    });
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toContain('/rest/v1/rpc/run_retention_cleanup');
    expect(calls[0].body).toMatchObject({
      p_batch_size: 100,
      p_dry_run: false,
    });
    expect(new Date(calls[0].body.p_security_context_before).toString()).not.toBe('Invalid Date');
  });

  it('supports a configured dry run without changing the RPC boundary', async () => {
    config.PLATFORM_CLEANUP_DRY_RUN = 'true';
    cleanupResult = { ...cleanupResult, dryRun: true, idempotencyDeletedCount: 0 };

    const response = await handleRetentionCleanup(workerRequest());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.cleanup.dryRun).toBe(true);
    expect(calls[0].body.p_dry_run).toBe(true);
  });

  it('requires explicit configuration outside Local and never exposes RPC failures', async () => {
    config.PLATFORM_RUNTIME_ENVIRONMENT = 'production';
    config.PLATFORM_CLEANUP_BATCH_SIZE = '';
    const invalid = await handleRetentionCleanup(workerRequest());
    expect(invalid.status).toBe(500);
    expect((await invalid.json()).error.code).toBe('CLEANUP_CONFIG_INVALID');
    expect(calls).toHaveLength(0);

    Object.assign(config, {
      PLATFORM_CLEANUP_BATCH_SIZE: '100',
      PLATFORM_CLEANUP_SECURITY_CONTEXT_RETENTION_SECONDS: '2592000',
      PLATFORM_CLEANUP_IDEMPOTENCY_RESPONSE_RETENTION_SECONDS: '0',
      PLATFORM_CLEANUP_DRY_RUN: 'false',
    });
    rpcStatus = 503;
    const unavailable = await handleRetentionCleanup(workerRequest());
    expect(unavailable.status).toBe(502);
    const unavailableBody = await unavailable.json();
    expect(unavailableBody).toEqual({
      error: {
        code: 'CLEANUP_UNAVAILABLE',
        message: 'The cleanup worker is unavailable.',
        requestId: expect.any(String),
      },
    });
  });

  it('rejects browser callers before reading cleanup configuration or database state', async () => {
    const response = await handleRetentionCleanup(
      workerRequest({ authorization: 'Bearer user-token' }),
    );
    expect(response.status).toBe(403);
    expect(calls).toHaveLength(0);
  });
});
