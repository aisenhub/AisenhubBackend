import { afterAll, afterEach, describe, expect, it, vi } from 'vitest';

const originalFetch = globalThis.fetch;
const orderId = '00000000-0000-4000-8000-000000000301';
const adminId = '00000000-0000-4000-8000-000000000002';
const orderSummary = {
  id: orderId,
  orderNo: 'AH-P5-QUERY-001',
  userId: '00000000-0000-4000-8000-000000000001',
  customerRef: '00000000-0000-4000-8000-000000000302',
  status: 'fulfilled',
  currency: 'USD',
  amountTotal: 2000,
  channel: 'local',
  itemCount: 1,
  createdAt: '2026-09-01T12:00:00.000Z',
  paidAt: '2026-09-01T12:01:00.000Z',
  fulfilledAt: '2026-09-01T12:01:00.000Z',
  cancelledAt: null,
  refundedAt: null,
};
const orderOverview = {
  order: orderSummary,
  items: [],
  payments: [],
  events: [],
  refunds: [],
  exceptions: [],
  auditTimeline: [],
};
const calls = [];

vi.stubGlobal('Deno', {
  env: {
    get(name) {
      return {
        SUPABASE_URL: 'http://local.supabase',
        SUPABASE_ANON_KEY: 'local-anon-key',
        SUPABASE_SERVICE_ROLE_KEY: 'local-service-role-key',
      }[name];
    },
  },
});
vi.stubGlobal(
  'fetch',
  vi.fn(async (url, init) => {
    const pathname = new URL(url).pathname;
    const body = init?.body ? JSON.parse(init.body) : {};
    calls.push({ pathname, body });
    if (pathname.endsWith('/resolve_app_origin')) {
      return new Response(JSON.stringify([{ app_slug: 'admin', environment: 'development' }]), {
        headers: { 'content-type': 'application/json' },
      });
    }
    if (pathname.endsWith('/get_admin_session')) {
      return new Response(
        JSON.stringify([
          {
            user_id: adminId,
            display_name: 'Local Admin',
            role: 'admin',
            aal: 'aal2',
            mfa_state: 'verified',
            expires_at: '2026-10-01T00:00:00.000Z',
          },
        ]),
        { headers: { 'content-type': 'application/json' } },
      );
    }
    if (pathname.endsWith('/admin_query_commerce_resource')) {
      return new Response(
        JSON.stringify([{ items: [orderSummary], page: { hasMore: false, nextCursor: null } }]),
        { headers: { 'content-type': 'application/json' } },
      );
    }
    if (pathname.endsWith('/admin_order_overview')) {
      return new Response(JSON.stringify([orderOverview]), {
        headers: { 'content-type': 'application/json' },
      });
    }
    throw new Error(`Unexpected RPC: ${pathname}`);
  }),
);

const { routePlatformAdmin } = await import('../../supabase/functions/_shared/admin-api.ts');

afterAll(() => {
  globalThis.fetch = originalFetch;
  vi.unstubAllGlobals();
});

afterEach(() => {
  calls.length = 0;
});

describe('Commerce Admin query routes', () => {
  it('maps Order list filters to the dedicated Commerce projection', async () => {
    const response = await routePlatformAdmin(
      new Request(
        'http://local.supabase/v1/admin/orders?search=QUERY&status=fulfilled&sort=orderNo',
        {
          headers: { Origin: 'http://localhost:5174', Cookie: '__Host-aisenhub_session=session' },
        },
      ),
    );

    expect(response.status).toBe(200);
    expect((await response.json()).data.items[0].orderNo).toBe('AH-P5-QUERY-001');
    expect(calls.at(-1)).toMatchObject({
      pathname: '/rest/v1/rpc/admin_query_commerce_resource',
      body: {
        p_resource: 'orders',
        p_search: 'QUERY',
        p_status: 'fulfilled',
        p_sort: 'orderNo',
      },
    });
  });

  it('serves one aggregate Order 360 request with refund/exception sections', async () => {
    const response = await routePlatformAdmin(
      new Request(`http://local.supabase/v1/admin/orders/${orderId}/overview`, {
        headers: { Origin: 'http://localhost:5174', Cookie: '__Host-aisenhub_session=session' },
      }),
    );

    expect(response.status).toBe(200);
    expect((await response.json()).data).toMatchObject({
      order: { id: orderId },
      refunds: [],
      exceptions: [],
      auditTimeline: [],
    });
    expect(calls.at(-1)).toMatchObject({
      pathname: '/rest/v1/rpc/admin_order_overview',
      body: { p_actor_id: adminId, p_order_id: orderId },
    });
  });

  it('requires an Admin platform session for Commerce queries', async () => {
    const response = await routePlatformAdmin(
      new Request('http://local.supabase/v1/admin/payments', {
        headers: { Origin: 'http://localhost:5174' },
      }),
    );

    expect(response.status).toBe(401);
    expect(calls).toHaveLength(1);
  });
});
