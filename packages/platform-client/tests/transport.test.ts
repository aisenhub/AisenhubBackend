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

describe('platform client transport', () => {
  it('uses credentialed requests, injects CSRF, and captures requestId', async () => {
    let receivedInit: RequestInit | undefined;
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test/',
      csrfToken: () => 'csrf-memory-token',
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
    expect(receivedInit?.credentials).toBe('include');
    expect(new Headers(receivedInit?.headers).get('x-csrf-token')).toBe('csrf-memory-token');
  });

  it('maps stable API errors and rejects malformed success payloads safely', async () => {
    const errorClient = createPlatformClient({
      baseUrl: 'https://api.example.test',
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
      fetch: async () => new Response(JSON.stringify({ data: { ok: 'yes' }, requestId })),
    });
    await expect(malformedClient.request('/v1/me', healthSchema)).rejects.toMatchObject({
      code: 'MALFORMED_API_RESPONSE',
      status: 200,
    });
  });

  it('provides typed session methods and derives the application declaration from options', async () => {
    const calls: Array<{ input: RequestInfo | URL; init?: RequestInit }> = [];
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test',
      appSlug: 'account',
      csrfToken: () => 'csrf-memory-token',
      fetch: async (input, init) => {
        calls.push({ input, init });
        const path = new URL(String(input)).pathname;
        if (path.endsWith('/session/exchange')) {
          return new Response(
            JSON.stringify({
              data: {
                authenticated: true,
                identity: {
                  userId: '00000000-0000-4000-8000-000000000001',
                  displayName: null,
                  avatarUrl: null,
                  locale: null,
                  status: 'active',
                },
                expiresAt: '2026-09-02T00:00:00.000Z',
                csrfToken: 'csrf-memory-token',
              },
              requestId,
            }),
            { headers: { 'content-type': 'application/json' } },
          );
        }
        if (init?.method === 'DELETE') {
          return new Response(JSON.stringify({ data: { revoked: true }, requestId }), {
            headers: { 'content-type': 'application/json' },
          });
        }
        return new Response(
          JSON.stringify({
            data: { authenticated: false, identity: null, expiresAt: null },
            requestId,
          }),
          { headers: { 'content-type': 'application/json' } },
        );
      },
    });

    await client.exchangeSession('supabase-access-token');
    await client.getSession();
    await client.logout();

    expect(calls).toHaveLength(3);
    expect(new Headers(calls[0].init?.headers).get('authorization')).toBe(
      'Bearer supabase-access-token',
    );
    for (const call of calls) {
      expect(new Headers(call.init?.headers).get('x-aisenhub-app')).toBe('account');
    }
  });

  it('provides typed catalog, entitlement, access, redemption, and feedback methods', async () => {
    const calls: Array<{ url: string; path: string; init?: RequestInit }> = [];
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test',
      publicBaseUrl: 'https://public.example.test',
      appSlug: 'account',
      csrfToken: () => 'csrf-memory-token',
      fetch: async (input, init) => {
        const path = new URL(String(input)).pathname;
        calls.push({ url: String(input), path, init });
        const data = path.endsWith('/products/public')
          ? {
              products: [
                {
                  sku: 'AISENLENS_PRO',
                  name: 'AisenLens Pro',
                  billingType: 'one_time',
                  version: 2,
                },
              ],
            }
          : path.endsWith('/me/entitlements')
            ? {
                entitlements: [
                  {
                    feature: 'lens.export',
                    value: { max: 10 },
                    sourceProduct: 'AISENLENS_PRO',
                    expiresAt: null,
                  },
                ],
              }
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

    await client.getPublicProducts();
    await client.getEntitlements();
    await client.checkAccess('lens.export');
    await client.redeem('AH-PRO-ABCD-2345', 'redeem-key-1');
    await client.submitFeedback({ kind: 'bug', title: 'Export issue', content: 'It failed.' });

    expect(calls.map(({ path }) => path)).toEqual([
      '/v1/products/public',
      '/v1/me/entitlements',
      '/v1/access/lens.export',
      '/v1/redemptions',
      '/v1/feedback',
    ]);
    expect(calls[0].path).toBe('/v1/products/public');
    expect(calls[0].url).toBe('https://public.example.test/v1/products/public');
    const redemptionHeaders = new Headers(calls[3].init?.headers);
    expect(redemptionHeaders.get('idempotency-key')).toBe('redeem-key-1');
    expect(redemptionHeaders.get('x-csrf-token')).toBe('csrf-memory-token');
    expect(JSON.parse(String(calls[3].init?.body))).toEqual({ code: 'AH-PRO-ABCD-2345' });
    expect(JSON.parse(String(calls[4].init?.body))).toEqual({
      kind: 'bug',
      title: 'Export issue',
      content: 'It failed.',
    });
  });

  it('requires a stable idempotency key and validates client inputs before sending', async () => {
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test',
      fetch: async () => {
        throw new Error('fetch should not be called');
      },
    });

    expect(() => client.redeem('AH-PRO-ABCD-2345', '  ')).toThrow(/Idempotency-Key/);
    expect(() => client.redeem('', 'redeem-key')).toThrow();
    expect(() => client.checkAccess('Invalid Feature')).toThrow(/feature code/);
    expect(() => client.submitFeedback({ kind: 'bug', title: '', content: 'x' })).toThrow();
  });

  it('sends fresh reauthentication tokens for deletion request commands', async () => {
    const calls: Array<{ path: string; init?: RequestInit }> = [];
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test',
      appSlug: 'account',
      csrfToken: () => 'csrf-memory-token',
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

    await client.requestAccountDeletion('fresh-token', 'deletion-key');
    await client.cancelAccountDeletion('fresh-token');

    expect(calls.map(({ path }) => path)).toEqual([
      '/v1/me/deletion-requests',
      '/v1/me/deletion-requests',
    ]);
    expect(new Headers(calls[0].init?.headers).get('authorization')).toBe('Bearer fresh-token');
    expect(new Headers(calls[0].init?.headers).get('idempotency-key')).toBe('deletion-key');
    expect(calls[0].init?.method).toBe('POST');
    expect(calls[1].init?.method).toBe('DELETE');
    expect(new Headers(calls[1].init?.headers).get('authorization')).toBe('Bearer fresh-token');
  });
});
