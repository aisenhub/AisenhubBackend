import { afterAll, afterEach, describe, expect, it, vi } from 'vitest';

const serviceRoleKey = 'local-service-role-key';
const calls = [];
let responseStatus = 200;
let role = 'owner';

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
    calls.push({ pathname, body: init?.body ? JSON.parse(init.body) : null });
    if (pathname.endsWith('/resolve_app_origin')) {
      return new Response(JSON.stringify([{ app_slug: 'admin', environment: 'development' }]));
    }
    if (pathname.endsWith('/get_admin_session')) {
      return new Response(
        JSON.stringify([
          {
            user_id: '10000000-0000-0000-0000-000000000001',
            display_name: 'Local Admin',
            role,
            aal: 'aal2',
            mfa_state: 'verified',
            expires_at: '2026-09-02T01:00:00.000Z',
          },
        ]),
      );
    }
    if (pathname.endsWith('/admin_operations_overview')) {
      if (responseStatus !== 200) return new Response('{}', { status: responseStatus });
      const cards = [
        {
          key: 'pending-orders',
          label: 'Pending orders',
          count: 1,
          severity: 'attention',
          href: '/orders?status=pending',
        },
        {
          key: 'paid-orders',
          label: 'Paid orders awaiting fulfillment',
          count: 0,
          severity: 'neutral',
          href: '/orders?status=paid',
        },
        {
          key: 'deletion-queue',
          label: 'Accounts awaiting deletion',
          count: 0,
          severity: 'neutral',
          href: '/users?status=deletion_pending',
        },
      ];
      if (role !== 'finance') {
        cards.push({
          key: 'open-feedback',
          label: 'Open feedback',
          count: 2,
          severity: 'attention',
          href: '/feedback?status=open',
        });
      } else {
        cards.push({
          key: 'chargeback-orders',
          label: 'Chargeback orders',
          count: 1,
          severity: 'critical',
          href: '/orders?status=chargeback',
        });
      }
      return new Response(JSON.stringify([{ generatedAt: '2026-09-02T00:00:00.000Z', cards }]));
    }
    return new Response('{}', { status: 404 });
  }),
);

const { routePlatformAdmin } = await import('../../supabase/functions/_shared/admin-api.ts');

function request() {
  return new Request('http://api.local/v1/admin/overview', {
    headers: {
      Origin: 'http://localhost:5174',
      'X-AisenHub-App': 'admin',
      Cookie: '__Host-aisenhub_session=valid-admin-session',
    },
  });
}

afterEach(() => {
  calls.length = 0;
  responseStatus = 200;
  role = 'owner';
});

afterAll(() => vi.unstubAllGlobals());

describe('Admin operations overview API', () => {
  it('preserves fixed drill-down links and role-safe card selection', async () => {
    const response = await routePlatformAdmin(request());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.cards.map((card) => card.href)).toEqual(
      expect.arrayContaining(['/orders?status=pending', '/feedback?status=open']),
    );
    expect(JSON.stringify(body)).not.toMatch(/sql|table|secret|token|password/i);
    expect(calls.at(-1).body).toEqual({ p_actor_id: '10000000-0000-0000-0000-000000000001' });
  });

  it('does not expose feedback metrics to finance and keeps finance operations actionable', async () => {
    role = 'finance';
    const response = await routePlatformAdmin(request());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.cards.some((card) => card.key === 'open-feedback')).toBe(false);
    expect(body.data.cards).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ key: 'chargeback-orders', href: '/orders?status=chargeback' }),
      ]),
    );
  });

  it('maps an unavailable aggregation to a stable error without upstream details', async () => {
    responseStatus = 503;
    const response = await routePlatformAdmin(request());
    const body = await response.json();

    expect(response.status).toBe(502);
    expect(body.error.code).toBe('INTERNAL_ERROR');
    expect(JSON.stringify(body)).not.toContain('503');
  });
});
