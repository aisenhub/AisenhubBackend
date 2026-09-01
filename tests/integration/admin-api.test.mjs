import { afterAll, afterEach, describe, expect, it, vi } from 'vitest';

const adminOrigin = 'http://localhost:5174';
const originalFetch = globalThis.fetch;
let adminSessionState = 'active';

async function mockedFetch(url, init) {
  const pathname = new URL(url).pathname;
  if (pathname.endsWith('/resolve_app_origin')) {
    const body = JSON.parse(init?.body ?? '{}');
    return new Response(
      JSON.stringify(
        body.p_origin === adminOrigin ? [{ app_slug: 'admin', environment: 'development' }] : [],
      ),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  if (pathname.endsWith('/get_admin_session')) {
    return new Response(
      JSON.stringify(
        adminSessionState === 'active'
          ? [
              {
                user_id: '10000000-0000-4000-0000-000000000002',
                display_name: 'Local Admin',
                role: 'admin',
                aal: 'aal1',
                mfa_state: 'required',
                expires_at: '2026-09-01T12:15:00.000Z',
              },
            ]
          : [],
      ),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  if (pathname.endsWith('/admin_query_resource')) {
    return new Response(
      JSON.stringify([
        {
          items: [
            {
              id: '20000000-0000-4000-8000-000000000003',
              slug: 'admin',
              name: 'AisenHub Admin',
              category: 'platform',
              status: 'active',
              originCount: 1,
              createdAt: '2026-09-01T12:00:00.000Z',
              updatedAt: '2026-09-01T12:00:00.000Z',
            },
          ],
          page: { hasMore: false, nextCursor: null },
        },
      ]),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  throw new Error(`Unexpected mocked request: ${pathname}`);
}

vi.stubGlobal('Deno', {
  env: {
    get(name) {
      return name === 'SUPABASE_URL' ? 'http://local.supabase' : 'local-anon-key';
    },
  },
});
vi.stubGlobal('fetch', vi.fn(mockedFetch));

const { routePlatformAdmin } = await import('../../supabase/functions/_shared/admin-api.ts');

afterAll(() => {
  globalThis.fetch = originalFetch;
  vi.unstubAllGlobals();
});

afterEach(() => {
  adminSessionState = 'active';
});

describe('platform Admin API', () => {
  it('requires a Platform Session before checking Admin membership', async () => {
    const response = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/session', {
        headers: { Origin: adminOrigin, 'X-AisenHub-App': 'admin' },
      }),
    );

    expect(response.status).toBe(401);
    expect((await response.json()).error.code).toBe('AUTHENTICATION_REQUIRED');
  });

  it('returns only the minimal active Admin identity and assurance state', async () => {
    const response = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/session', {
        headers: {
          Origin: adminOrigin,
          'X-AisenHub-App': 'admin',
          Cookie: '__Host-aisenhub_session=valid-admin-session',
        },
      }),
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data).toEqual({
      authenticated: true,
      identity: {
        userId: '10000000-0000-4000-0000-000000000002',
        displayName: 'Local Admin',
      },
      role: 'admin',
      aal: 'aal1',
      mfaState: 'required',
      expiresAt: '2026-09-01T12:15:00.000Z',
    });
    expect(body.data).not.toHaveProperty('permissions');
    expect(JSON.stringify(body)).not.toMatch(/token|hash|database|grant|secret/i);
    expect(response.headers.get('access-control-allow-origin')).toBe(adminOrigin);
    expect(response.headers.get('access-control-allow-credentials')).toBe('true');
  });

  it('denies non-admin, disabled, expired, revoked, and unknown sessions uniformly', async () => {
    adminSessionState = 'denied';
    const response = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/session', {
        headers: {
          Origin: adminOrigin,
          'X-AisenHub-App': 'admin',
          Cookie: '__Host-aisenhub_session=denied-session',
        },
      }),
    );
    const body = await response.json();

    expect(response.status).toBe(403);
    expect(body.error.code).toBe('ADMIN_ACCESS_DENIED');
    expect(JSON.stringify(body)).not.toMatch(/token|hash|database|grant|secret|stack/i);
  });

  it('rejects forged Origins and unsupported methods', async () => {
    const origin = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/session', {
        headers: {
          Origin: 'https://attacker.example',
          'X-AisenHub-App': 'admin',
          Cookie: '__Host-aisenhub_session=valid-admin-session',
        },
      }),
    );
    expect(origin.status).toBe(403);
    expect((await origin.json()).error.code).toBe('ORIGIN_NOT_ALLOWED');

    const method = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/session', {
        method: 'POST',
        headers: { Origin: adminOrigin, 'X-AisenHub-App': 'admin' },
      }),
    );
    expect(method.status).toBe(405);
    expect((await method.json()).error.code).toBe('VALIDATION_ERROR');
  });

  it('answers Admin preflight with the exact registered Origin', async () => {
    const response = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/session', {
        method: 'OPTIONS',
        headers: {
          Origin: adminOrigin,
          'Access-Control-Request-Method': 'GET',
          'Access-Control-Request-Headers': 'X-AisenHub-App',
        },
      }),
    );

    expect(response.status).toBe(204);
    expect(response.headers.get('access-control-allow-origin')).toBe(adminOrigin);
    expect(response.headers.get('access-control-allow-credentials')).toBe('true');
  });

  it('serves an authenticated allowlisted query and system health projection', async () => {
    const query = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/applications?limit=1&sort=slug&direction=asc', {
        headers: {
          Origin: adminOrigin,
          'X-AisenHub-App': 'admin',
          Cookie: '__Host-aisenhub_session=valid-admin-session',
        },
      }),
    );
    const queryBody = await query.json();
    expect(query.status).toBe(200);
    expect(queryBody.data.items[0].slug).toBe('admin');
    expect(queryBody.data).not.toHaveProperty('sql');
    expect(JSON.stringify(queryBody)).not.toMatch(/hash|secret|password/i);

    const health = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/system-health', {
        headers: {
          Origin: adminOrigin,
          'X-AisenHub-App': 'admin',
          Cookie: '__Host-aisenhub_session=valid-admin-session',
        },
      }),
    );
    const healthBody = await health.json();
    expect(health.status).toBe(200);
    expect(healthBody.data.status).toBe('healthy');
    expect(healthBody.data.checks).toHaveLength(3);
  });
});
