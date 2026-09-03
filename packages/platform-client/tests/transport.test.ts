import { describe, expect, it } from 'vitest';

import { createPlatformClient, PlatformClientError } from '../src/index';

interface HealthPayload {
  ok: boolean;
}

const healthSchema = {
  parse(input: unknown): HealthPayload {
    if (
      typeof input !== 'object' ||
      input === null ||
      !('ok' in input) ||
      typeof input.ok !== 'boolean'
    ) {
      throw new Error('Invalid health payload');
    }
    return { ok: input.ok };
  },
};

const requestId = '00000000-0000-4000-8000-000000000002';
const accessToken = 'supabase-access-token';

describe('platform client transport', () => {
  it('uses bearer-only requests and captures requestId', async () => {
    let receivedInit: RequestInit | undefined;
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test/',
      accessToken: () => accessToken,
      fetch: async (_input, init) => {
        receivedInit = init;
        return new Response(JSON.stringify({ data: { ok: true }, requestId }), {
          headers: { 'content-type': 'application/json', 'x-request-id': requestId },
          status: 200,
        });
      },
    });

    await expect(client.request('/v1/health', healthSchema)).resolves.toEqual({
      data: { ok: true },
      requestId,
    });
    expect(receivedInit?.credentials).toBe('omit');
    const headers = new Headers(receivedInit?.headers);
    expect(headers.get('authorization')).toBe(`Bearer ${accessToken}`);
    expect(headers.get('cookie')).toBeNull();
    expect(headers.get('x-csrf-token')).toBeNull();
    expect(headers.get('x-aisenhub-app')).toBeNull();
  });

  it('maps stable API errors and rejects malformed success payloads safely', async () => {
    const errorClient = createPlatformClient({
      baseUrl: 'https://api.example.test',
      accessToken: () => accessToken,
      fetch: async () =>
        new Response(
          JSON.stringify({
            error: { code: 'VALIDATION_ERROR', message: 'Invalid input.', requestId },
          }),
          { status: 422 },
        ),
    });

    await expect(errorClient.request('/v1/me', healthSchema)).rejects.toMatchObject<
      Partial<PlatformClientError>
    >({
      code: 'VALIDATION_ERROR',
      requestId,
      status: 422,
    });

    const malformedClient = createPlatformClient({
      baseUrl: 'https://api.example.test',
      accessToken: () => accessToken,
      fetch: async () => new Response(JSON.stringify({ data: { ok: 'yes' }, requestId })),
    });
    await expect(malformedClient.request('/v1/me', healthSchema)).rejects.toMatchObject({
      code: 'MALFORMED_API_RESPONSE',
      status: 200,
    });
  });

  it('uses the new account and application route boundaries', async () => {
    const calls: Array<{ url: string; init?: RequestInit }> = [];
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test',
      publicBaseUrl: 'https://public.example.test',
      accessToken: () => accessToken,
      fetch: async (input, init) => {
        const url = String(input);
        calls.push({ url, init });
        const path = new URL(url).pathname;
        const data = path.endsWith('/products/public')
          ? { products: [] }
          : path.endsWith('/account/me')
            ? {
                profile: {
                  userId: '00000000-0000-4000-8000-000000000001',
                  displayName: null,
                  avatarUrl: null,
                  locale: null,
                  status: 'active',
                },
              }
            : path.endsWith('/app/context')
              ? {
                  userId: '00000000-0000-4000-8000-000000000001',
                  clientId: 'account-local-web',
                  application: {
                    id: '00000000-0000-4000-8000-000000000101',
                    slug: 'account',
                  },
                  membershipId: '00000000-0000-4000-8000-000000000201',
                  membershipStatus: 'active',
                  aal: 'aal1',
                }
              : { applications: [] };
        return new Response(JSON.stringify({ data, requestId }), {
          headers: { 'content-type': 'application/json' },
        });
      },
    });

    await client.getPublicProducts();
    await client.getProfile();
    await client.getApplicationContext();
    await client.getApplications();

    expect(calls.map(({ url }) => new URL(url).pathname)).toEqual([
      '/v1/products/public',
      '/v1/account/me',
      '/v1/app/context',
      '/v1/account/applications',
    ]);
    expect(new Headers(calls[0].init?.headers).get('authorization')).toBeNull();
    for (const call of calls.slice(1)) {
      expect(new Headers(call.init?.headers).get('authorization')).toBe(`Bearer ${accessToken}`);
      expect(call.init?.credentials).toBe('omit');
    }
  });

  it('provides typed app data commands without CSRF or app declaration headers', async () => {
    const calls: Array<{ path: string; init?: RequestInit }> = [];
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test',
      accessToken: () => accessToken,
      fetch: async (input, init) => {
        const path = new URL(String(input)).pathname;
        calls.push({ path, init });
        const data = path.endsWith('/entitlements')
          ? { entitlements: [] }
          : path.includes('/access/')
            ? {
                allowed: true,
                feature: 'lens.export',
                value: { max: 10 },
                sourceProduct: 'AISENLENS_PRO',
                expiresAt: null,
                decisionId: requestId,
              }
            : path.endsWith('/redemptions')
              ? {
                  redemptionId: requestId,
                  grantId: '00000000-0000-4000-8000-000000000003',
                  status: 'redeemed',
                }
              : {
                  id: '00000000-0000-4000-8000-000000000004',
                  status: 'open',
                  createdAt: '2026-09-01T12:00:00.000Z',
                };
        return new Response(JSON.stringify({ data, requestId }), {
          headers: { 'content-type': 'application/json' },
        });
      },
    });

    await client.getEntitlements();
    await client.checkAccess('lens.export');
    await client.redeem('AH-PRO-ABCD-2345', 'redeem-key-1');
    await client.submitFeedback({ kind: 'bug', title: 'Export issue', content: 'It failed.' });

    expect(calls.map(({ path }) => path)).toEqual([
      '/v1/app/entitlements',
      '/v1/app/access/lens.export',
      '/v1/app/redemptions',
      '/v1/app/feedback',
    ]);
    const redemptionHeaders = new Headers(calls[2].init?.headers);
    expect(redemptionHeaders.get('idempotency-key')).toBe('redeem-key-1');
    expect(redemptionHeaders.get('x-csrf-token')).toBeNull();
    expect(redemptionHeaders.get('x-aisenhub-app')).toBeNull();
    expect(JSON.parse(String(calls[2].init?.body))).toEqual({ code: 'AH-PRO-ABCD-2345' });
  });

  it('validates idempotency keys and client inputs before sending', async () => {
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test',
      accessToken: () => accessToken,
      fetch: async () => {
        throw new Error('fetch should not be called');
      },
    });

    expect(() => client.redeem('AH-PRO-ABCD-2345', '  ')).toThrow(/Idempotency-Key/);
    expect(() => client.redeem('', 'redeem-key')).toThrow();
    expect(() => client.checkAccess('Invalid Feature')).toThrow(/feature code/);
    expect(() => client.submitFeedback({ kind: 'bug', title: '', content: 'x' })).toThrow();
  });

  it('uses the authenticated account token for deletion commands', async () => {
    const calls: Array<{ path: string; init?: RequestInit }> = [];
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test',
      accessToken: () => accessToken,
      fetch: async (input, init) => {
        calls.push({ path: new URL(String(input)).pathname, init });
        const data = {
          deletionRequestId: '00000000-0000-4000-8000-000000000050',
          status: init?.method === 'DELETE' ? 'cancelled' : 'pending',
          executeAfter: '2026-09-01T12:00:00.000Z',
          requestedAt: '2026-09-01T12:00:00.000Z',
          completedAt: null,
        };
        return new Response(JSON.stringify({ data, requestId }), {
          headers: { 'content-type': 'application/json' },
        });
      },
    });

    await client.requestAccountDeletion('deletion-key');
    await client.cancelAccountDeletion();

    expect(calls.map(({ path }) => path)).toEqual([
      '/v1/account/deletion-requests',
      '/v1/account/deletion-requests',
    ]);
    expect(new Headers(calls[0].init?.headers).get('authorization')).toBe(`Bearer ${accessToken}`);
    expect(calls[0].init?.method).toBe('POST');
    expect(calls[1].init?.method).toBe('DELETE');
  });
});
