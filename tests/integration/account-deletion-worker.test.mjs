import { afterAll, afterEach, describe, expect, it, vi } from 'vitest';

const originalFetch = globalThis.fetch;
const serviceRoleKey = 'local-service-role-key';
const userId = '00000000-0000-4000-8000-000000000001';
const deletionRequestId = '00000000-0000-4000-8000-000000000050';
const calls = [];
let authStatus = 200;
let claimResult = {
  deletion_request_id: deletionRequestId,
  user_id: userId,
  status: 'processing',
  attempt_count: 1,
};

vi.stubGlobal('Deno', {
  env: {
    get(name) {
      return {
        SUPABASE_URL: 'http://local.supabase',
        SUPABASE_ANON_KEY: 'local-anon-key',
        SUPABASE_SERVICE_ROLE_KEY: serviceRoleKey,
      }[name];
    },
  },
});
vi.stubGlobal(
  'fetch',
  vi.fn(async (url, init) => {
    const pathname = new URL(url).pathname;
    const body = init?.body ? JSON.parse(init.body) : null;
    calls.push({ pathname, headers: Object.fromEntries(new Headers(init.headers)), body });
    if (pathname.endsWith('/auth/v1/admin/users/' + userId)) {
      return new Response('{}', { status: authStatus });
    }
    if (pathname.endsWith('/claim_account_deletion_request')) {
      return new Response(JSON.stringify([claimResult]), {
        headers: { 'content-type': 'application/json' },
      });
    }
    if (pathname.endsWith('/complete_account_deletion_request')) {
      return new Response(
        JSON.stringify([
          {
            deletionRequestId: deletionRequestId,
            userId,
            status: 'completed',
            completedAt: '2026-09-02T12:00:00.000Z',
            revokedGrantCount: 2,
            deletedSessionCount: 1,
            anonymizedFeedbackCount: 1,
            detachedOrderCount: 1,
            disabledAdminCount: 0,
            idempotent: false,
          },
        ]),
        { headers: { 'content-type': 'application/json' } },
      );
    }
    if (pathname.endsWith('/fail_account_deletion_request')) {
      return new Response(
        JSON.stringify([
          {
            deletion_request_id: deletionRequestId,
            status: 'failed',
            attempt_count: 1,
            next_attempt_at: '2026-09-02T12:05:00.000Z',
            last_error_code: 'AUTH_USER_UPDATE_FAILED',
          },
        ]),
        { headers: { 'content-type': 'application/json' } },
      );
    }
    throw new Error(`Unexpected worker call: ${pathname}`);
  }),
);

const { handleDeletionWorker } =
  await import('../../supabase/functions/account-deletion-worker/index.ts');

function workerRequest(headers = {}) {
  return new Request('http://local.supabase/functions/v1/account-deletion-worker', {
    method: 'POST',
    headers: { authorization: `Bearer ${serviceRoleKey}`, ...headers },
  });
}

afterAll(() => {
  globalThis.fetch = originalFetch;
  vi.unstubAllGlobals();
});

afterEach(() => {
  calls.length = 0;
  authStatus = 200;
  claimResult = {
    deletion_request_id: deletionRequestId,
    user_id: userId,
    status: 'processing',
    attempt_count: 1,
  };
});

describe('retryable account deletion worker', () => {
  it('anonymizes Auth first, then completes the atomic database workflow', async () => {
    const response = await handleDeletionWorker(workerRequest());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.deletion.status).toBe('completed');
    expect(body.data.deletion.revokedGrantCount).toBe(2);
    expect(calls.map((call) => call.pathname)).toEqual([
      '/rest/v1/rpc/claim_account_deletion_request',
      `/auth/v1/admin/users/${userId}`,
      '/rest/v1/rpc/complete_account_deletion_request',
    ]);
    expect(calls[1].body.ban_duration).toBe('876000h');
    expect(calls[1].body.password).toBeTruthy();
    expect(calls[2].body).toMatchObject({
      p_deletion_request_id: deletionRequestId,
      p_request_id: body.requestId,
    });
    expect(JSON.stringify(calls[2].body)).not.toContain(calls[1].body.password);
  });

  it('records a stable retryable error when Auth update fails', async () => {
    authStatus = 503;
    const response = await handleDeletionWorker(workerRequest());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.deletion).toMatchObject({
      status: 'failed',
      last_error_code: 'AUTH_USER_UPDATE_FAILED',
    });
    expect(calls.map((call) => call.pathname)).toEqual([
      '/rest/v1/rpc/claim_account_deletion_request',
      `/auth/v1/admin/users/${userId}`,
      '/rest/v1/rpc/fail_account_deletion_request',
    ]);
    expect(JSON.stringify(body)).not.toContain('503');
  });

  it('rejects browser callers before claiming a deletion request', async () => {
    const response = await handleDeletionWorker(
      workerRequest({ authorization: 'Bearer user-token' }),
    );

    expect(response.status).toBe(403);
    expect(calls).toHaveLength(0);
  });
});
