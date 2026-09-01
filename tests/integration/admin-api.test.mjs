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
        adminSessionState === 'active' || adminSessionState === 'mfa-ok'
          ? [
              {
                user_id: '10000000-0000-4000-0000-000000000002',
                display_name: 'Local Admin',
                role: 'admin',
                aal: adminSessionState === 'mfa-ok' ? 'aal2' : 'aal1',
                mfa_state: adminSessionState === 'mfa-ok' ? 'verified' : 'required',
                expires_at: '2026-09-01T12:15:00.000Z',
              },
            ]
          : [],
      ),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  if (pathname.endsWith('/verify_platform_csrf')) {
    return new Response(JSON.stringify([{ valid: true }]), {
      headers: { 'content-type': 'application/json' },
    });
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
  if (pathname.endsWith('/admin_query_catalog_resource')) {
    return new Response(
      JSON.stringify([
        {
          items: [
            {
              id: '21000000-0000-4000-8000-000000000001',
              appId: '20000000-0000-4000-8000-000000000002',
              appSlug: 'account',
              environment: 'development',
              origin: 'http://localhost:5173',
              isActive: true,
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
  if (pathname.endsWith('/admin_product_overview')) {
    return new Response(
      JSON.stringify([
        {
          product: { id: '23000000-0000-4000-8000-000000000001', sku: 'AISENLENS_LIFETIME' },
          versions: [],
          prices: [],
          featureSnapshots: [],
          redemptionBatches: [],
          auditLogs: [],
        },
      ]),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  if (pathname.endsWith('/admin_catalog_resource_detail')) {
    return new Response(
      JSON.stringify([
        {
          id: '21000000-0000-4000-8000-000000000001',
          appId: '20000000-0000-4000-8000-000000000002',
          appSlug: 'account',
          environment: 'development',
          origin: 'http://localhost:5173',
          isActive: true,
          createdAt: '2026-09-01T12:00:00.000Z',
          updatedAt: '2026-09-01T12:00:00.000Z',
        },
      ]),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  if (pathname.endsWith('/admin_catalog_draft_command')) {
    return new Response(
      JSON.stringify([
        {
          id: '22000000-0000-4000-8000-000000000001',
          slug: 'draft-app',
          name: 'Draft App',
          category: 'tool',
          status: 'draft',
          originCount: 0,
          createdAt: '2026-09-01T12:00:00.000Z',
          updatedAt: '2026-09-01T12:00:00.000Z',
        },
      ]),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  if (pathname.endsWith('/admin_catalog_command')) {
    return new Response(
      JSON.stringify([
        {
          productVersionId: '22000000-0000-4000-8000-000000000002',
          status: 'published',
          publishedAt: '2026-09-01T12:00:00.000Z',
          auditLogId: '22000000-0000-4000-8000-000000000003',
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

  it('serves Catalog projections and Product overview through explicit Admin routes', async () => {
    const origins = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/origins?limit=10&sort=origin&direction=asc', {
        headers: {
          Origin: adminOrigin,
          'X-AisenHub-App': 'admin',
          Cookie: '__Host-aisenhub_session=valid-admin-session',
        },
      }),
    );
    expect(origins.status).toBe(200);
    expect((await origins.json()).data.items[0].appSlug).toBe('account');

    const overview = await routePlatformAdmin(
      new Request(
        'http://api.local/v1/admin/products/23000000-0000-4000-8000-000000000001/overview',
        {
          headers: {
            Origin: adminOrigin,
            'X-AisenHub-App': 'admin',
            Cookie: '__Host-aisenhub_session=valid-admin-session',
          },
        },
      ),
    );
    expect(overview.status).toBe(200);
    expect((await overview.json()).data.product.sku).toBe('AISENLENS_LIFETIME');

    const detail = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/origins/21000000-0000-4000-8000-000000000001', {
        headers: {
          Origin: adminOrigin,
          'X-AisenHub-App': 'admin',
          Cookie: '__Host-aisenhub_session=valid-admin-session',
        },
      }),
    );
    expect(detail.status).toBe(200);
    expect((await detail.json()).data.origin).toBe('http://localhost:5173');
  });

  it('protects explicit Catalog draft mutations with CSRF, Admin RBAC, and idempotency', async () => {
    adminSessionState = 'mfa-ok';
    const response = await routePlatformAdmin(
      new Request('http://api.local/v1/admin/applications', {
        method: 'POST',
        headers: {
          Origin: adminOrigin,
          'X-AisenHub-App': 'admin',
          'X-CSRF-Token': 'csrf-token',
          'Idempotency-Key': 'draft-app-create-1',
          Cookie: '__Host-aisenhub_session=valid-admin-session',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          slug: 'draft-app',
          name: 'Draft App',
          category: 'tool',
          reason: 'catalog setup',
        }),
      }),
    );

    expect(response.status).toBe(201);
    expect((await response.json()).data.slug).toBe('draft-app');
  });

  it('protects high-risk Catalog commands with typed confirmation and permission-specific MFA', async () => {
    const missingMfa = await routePlatformAdmin(
      new Request(
        'http://api.local/v1/admin/product-versions/22000000-0000-4000-8000-000000000002/publish',
        {
          method: 'POST',
          headers: {
            Origin: adminOrigin,
            'X-AisenHub-App': 'admin',
            'X-CSRF-Token': 'csrf-token',
            'Idempotency-Key': 'publish-without-mfa',
            Cookie: '__Host-aisenhub_session=valid-admin-session',
            'content-type': 'application/json',
          },
          body: JSON.stringify({ reason: 'release', confirmation: true }),
        },
      ),
    );
    expect(missingMfa.status).toBe(403);
    expect((await missingMfa.json()).error.code).toBe('MFA_REQUIRED');

    adminSessionState = 'mfa-ok';
    const response = await routePlatformAdmin(
      new Request(
        'http://api.local/v1/admin/product-versions/22000000-0000-4000-8000-000000000002/publish',
        {
          method: 'POST',
          headers: {
            Origin: adminOrigin,
            'X-AisenHub-App': 'admin',
            'X-CSRF-Token': 'csrf-token',
            'Idempotency-Key': 'publish-with-mfa',
            Cookie: '__Host-aisenhub_session=valid-admin-session',
            'content-type': 'application/json',
          },
          body: JSON.stringify({ reason: 'release', confirmation: true }),
        },
      ),
    );
    expect(response.status).toBe(200);
    expect((await response.json()).data.auditLogId).toBe('22000000-0000-4000-8000-000000000003');
  });
});
