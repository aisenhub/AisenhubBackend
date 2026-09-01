import { afterAll, afterEach, describe, expect, it, vi } from 'vitest';

const accountOrigin = 'http://localhost:5173';
const userId = '00000000-0000-4000-8000-000000000001';
const originalFetch = globalThis.fetch;
let csrfIsValid = true;
let lastServiceCall = null;

function response(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

async function mockedFetch(url, init) {
  const pathname = new URL(url).pathname;
  const body = JSON.parse(init?.body ?? '{}');
  if (pathname.endsWith('/resolve_app_origin')) {
    return response(
      body.p_origin === accountOrigin ? [{ app_slug: 'account', environment: 'development' }] : [],
    );
  }
  if (pathname.endsWith('/auth/v1/user')) {
    return response({ id: userId });
  }
  if (pathname.endsWith('/get_platform_session')) {
    return response([
      {
        user_id: userId,
        profile_status: 'active',
      },
    ]);
  }
  if (pathname.endsWith('/verify_platform_csrf')) return response([{ valid: csrfIsValid }]);
  if (pathname.endsWith('/get_public_products')) {
    return response([
      {
        sku: 'AISENLENS_PRO',
        name: 'AisenLens Pro',
        billing_type: 'one_time',
        version: 2,
        internal_price_strategy: 'should-never-escape',
      },
    ]);
  }
  if (pathname.endsWith('/check_access')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        allowed: true,
        feature: 'lens.export',
        value: { max: 10 },
        source_product: 'AISENLENS_PRO',
        expires_at: null,
        decision_id: '00000000-0000-4000-8000-000000000020',
      },
    ]);
  }
  if (pathname.endsWith('/list_user_entitlements')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        feature: 'lens.export',
        value: { max: 10 },
        source_product: 'AISENLENS_PRO',
        expires_at: null,
      },
    ]);
  }
  if (pathname.endsWith('/redeem_code')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        redemption_id: '00000000-0000-4000-8000-000000000030',
        grant_id: '00000000-0000-4000-8000-000000000031',
        status: 'redeemed',
      },
    ]);
  }
  if (pathname.endsWith('/create_feedback')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        id: '00000000-0000-4000-8000-000000000040',
        status: 'open',
        created_at: '2026-09-01T12:00:00.000Z',
      },
    ]);
  }
  if (pathname.endsWith('/request_account_deletion')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        deletion_request_id: '00000000-0000-4000-8000-000000000050',
        status: 'pending',
        execute_after: '2026-09-01T12:00:00.000Z',
        requested_at: '2026-09-01T12:00:00.000Z',
        completed_at: null,
      },
    ]);
  }
  if (pathname.endsWith('/cancel_account_deletion')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        deletion_request_id: '00000000-0000-4000-8000-000000000050',
        status: 'cancelled',
        execute_after: '2026-09-01T12:00:00.000Z',
        requested_at: '2026-09-01T12:00:00.000Z',
        completed_at: null,
      },
    ]);
  }
  throw new Error(`Unexpected mocked request: ${pathname}`);
}

vi.stubGlobal('Deno', {
  env: {
    get(name) {
      const values = {
        SUPABASE_URL: 'http://local.supabase',
        SUPABASE_ANON_KEY: 'local-anon-key',
        SUPABASE_SERVICE_ROLE_KEY: 'local-service-role-key',
        REDEMPTION_PEPPER: 'local-test-pepper',
        REDEMPTION_PEPPER_VERSION: '1',
      };
      return values[name];
    },
  },
});
vi.stubGlobal('fetch', vi.fn(mockedFetch));

const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
const { routePlatformPublic } = await import('../../supabase/functions/_shared/public-api.ts');

afterAll(() => {
  globalThis.fetch = originalFetch;
  vi.unstubAllGlobals();
});

afterEach(() => {
  csrfIsValid = true;
  lastServiceCall = null;
});

function sessionHeaders() {
  return {
    Origin: accountOrigin,
    'X-AisenHub-App': 'account',
    Cookie: '__Host-aisenhub_session=session-token',
  };
}

describe('public catalog and account API', () => {
  it('returns only the public product projection', async () => {
    const response = await routePlatformPublic(
      new Request('http://api.local/v1/products/public', { headers: { Origin: accountOrigin } }),
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.products).toEqual([
      { sku: 'AISENLENS_PRO', name: 'AisenLens Pro', billingType: 'one_time', version: 2 },
    ]);
    expect(JSON.stringify(body)).not.toContain('internal_price_strategy');
  });

  it('resolves access using the verified application and session user', async () => {
    const response = await routePlatformApi(
      new Request('http://api.local/v1/access/lens.export', { headers: sessionHeaders() }),
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data).toEqual({
      allowed: true,
      feature: 'lens.export',
      value: { max: 10 },
      sourceProduct: 'AISENLENS_PRO',
      expiresAt: null,
      decisionId: '00000000-0000-4000-8000-000000000020',
    });
    expect(lastServiceCall.body).toEqual({
      p_user_id: userId,
      p_app_slug: 'account',
      p_feature_code: 'lens.export',
    });
  });

  it('lists entitlements without exposing internal grant identifiers', async () => {
    const response = await routePlatformApi(
      new Request('http://api.local/v1/me/entitlements', { headers: sessionHeaders() }),
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.entitlements[0]).toEqual({
      feature: 'lens.export',
      value: { max: 10 },
      sourceProduct: 'AISENLENS_PRO',
      expiresAt: null,
    });
    expect(JSON.stringify(body)).not.toMatch(/grant|audit|hash/i);
  });

  it('hashes redemption input before sending it to the server command', async () => {
    const response = await routePlatformApi(
      new Request('http://api.local/v1/redemptions', {
        method: 'POST',
        headers: {
          ...sessionHeaders(),
          'X-CSRF-Token': 'valid-token',
          'Idempotency-Key': 'redeem-request-1',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ code: 'ah-pro-ABCD-2345' }),
      }),
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.status).toBe('redeemed');
    expect(lastServiceCall.body.p_code_hash).toMatch(/^[a-f0-9]{64}$/);
    expect(JSON.stringify(lastServiceCall.body)).not.toContain('AH-PRO-ABCD-2345');
    expect(lastServiceCall.body.p_user_id).toBe(userId);
  });

  it('attributes feedback to the verified app instead of client input', async () => {
    const response = await routePlatformApi(
      new Request('http://api.local/v1/feedback', {
        method: 'POST',
        headers: {
          ...sessionHeaders(),
          'X-CSRF-Token': 'valid-token',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          kind: 'bug',
          title: 'Export issue',
          content: 'The export button does not respond.',
          appId: 'forged-app-id',
        }),
      }),
    );
    const body = await response.json();

    expect(response.status).toBe(201);
    expect(body.data.status).toBe('open');
    expect(lastServiceCall.body.p_app_slug).toBe('account');
    expect(lastServiceCall.body).not.toHaveProperty('appId');
  });

  it('applies session, CSRF, and origin gates to account commands', async () => {
    const noSession = await routePlatformApi(
      new Request('http://api.local/v1/me/entitlements', { headers: { Origin: accountOrigin } }),
    );
    expect(noSession.status).toBe(401);

    csrfIsValid = false;
    const noCsrf = await routePlatformApi(
      new Request('http://api.local/v1/feedback', {
        method: 'POST',
        headers: sessionHeaders(),
        body: JSON.stringify({ kind: 'bug', title: 'x', content: 'y' }),
      }),
    );
    expect(noCsrf.status).toBe(403);
    expect((await noCsrf.json()).error.code).toBe('CSRF_INVALID');

    const noOrigin = await routePlatformApi(
      new Request('http://api.local/v1/access/lens.export', {
        headers: { Cookie: '__Host-aisenhub_session=session-token' },
      }),
    );
    expect(noOrigin.status).toBe(403);
    expect((await noOrigin.json()).error.code).toBe('ORIGIN_NOT_ALLOWED');
  });

  it('requires a fresh Auth token and keeps deletion request state server-owned', async () => {
    const response = await routePlatformApi(
      new Request('http://api.local/v1/me/deletion-requests', {
        method: 'POST',
        headers: {
          Origin: accountOrigin,
          'X-AisenHub-App': 'account',
          Authorization: 'Bearer freshly-reauthenticated-token',
          'Idempotency-Key': 'deletion-request-1',
          'Content-Type': 'application/json',
        },
        body: '{}',
      }),
    );
    const body = await response.json();

    expect(response.status).toBe(202);
    expect(body.data).toEqual({
      deletionRequestId: '00000000-0000-4000-8000-000000000050',
      status: 'pending',
      executeAfter: '2026-09-01T12:00:00.000Z',
      requestedAt: '2026-09-01T12:00:00.000Z',
      completedAt: null,
    });
    expect(lastServiceCall.body.p_user_id).toBe(userId);
    expect(lastServiceCall.body).not.toHaveProperty('execute_after');
    expect(lastServiceCall.body.p_request_hash).toMatch(/^[a-f0-9]{64}$/);
  });

  it('allows cancellation after reauthentication even when platform sessions were revoked', async () => {
    const response = await routePlatformApi(
      new Request('http://api.local/v1/me/deletion-requests', {
        method: 'DELETE',
        headers: {
          Origin: accountOrigin,
          'X-AisenHub-App': 'account',
          Authorization: 'Bearer freshly-reauthenticated-token',
        },
      }),
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.status).toBe('cancelled');
    expect(lastServiceCall.pathname).toContain('cancel_account_deletion');
    expect(lastServiceCall.body.p_user_id).toBe(userId);
  });

  it('rejects deletion without reauthentication', async () => {
    const response = await routePlatformApi(
      new Request('http://api.local/v1/me/deletion-requests', {
        method: 'POST',
        headers: {
          Origin: accountOrigin,
          'X-AisenHub-App': 'account',
          'Idempotency-Key': 'deletion-request-2',
          'Content-Type': 'application/json',
        },
        body: '{}',
      }),
    );

    expect(response.status).toBe(401);
    expect((await response.json()).error.code).toBe('REAUTHENTICATION_REQUIRED');
  });
});
