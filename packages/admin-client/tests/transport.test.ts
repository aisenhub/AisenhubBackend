import { describe, expect, it } from 'vitest';

import {
  AdminClientError,
  createAdminClient,
  createAdminDataProvider,
  withIdempotencyKey,
} from '../src/index';

interface AdminHealthPayload {
  ok: boolean;
}

const adminHealthSchema = {
  parse(input: unknown): AdminHealthPayload {
    if (
      typeof input !== 'object' ||
      input === null ||
      !('ok' in input) ||
      typeof input.ok !== 'boolean'
    ) {
      throw new Error('Invalid admin health payload');
    }
    return { ok: input.ok };
  },
};

const requestId = '00000000-0000-4000-8000-000000000003';

describe('admin client transport', () => {
  it('attaches idempotency and CSRF headers without persistent storage', async () => {
    let receivedInit: RequestInit | undefined;
    const client = createAdminClient({
      baseUrl: 'https://api.example.test/',
      csrfToken: () => 'csrf-memory-token',
      fetch: async (_input, init) => {
        receivedInit = init;
        return new Response(JSON.stringify({ data: { ok: true }, requestId }), {
          headers: { 'content-type': 'application/json' },
          status: 200,
        });
      },
    });

    const init = withIdempotencyKey({ method: 'POST' }, 'idem-001');
    await expect(client.request('/v1/admin/operation', adminHealthSchema, init)).resolves.toEqual({
      data: { ok: true },
      requestId,
    });
    expect(init.idempotencyKey).toBe('idem-001');
    expect(new Headers(receivedInit?.headers).get('Idempotency-Key')).toBe('idem-001');
    expect(new Headers(receivedInit?.headers).get('x-csrf-token')).toBe('csrf-memory-token');
  });

  it('maps stable errors and rejects malformed responses', async () => {
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async () =>
        new Response(
          JSON.stringify({ error: { code: 'MFA_REQUIRED', message: 'MFA required.', requestId } }),
          {
            status: 403,
          },
        ),
    });

    await expect(client.request('/v1/admin/operation', adminHealthSchema)).rejects.toMatchObject<
      Partial<AdminClientError>
    >({
      code: 'MFA_REQUIRED',
      requestId,
      status: 403,
    });

    const malformedClient = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async () => new Response('not json', { status: 200 }),
    });
    await expect(
      malformedClient.request('/v1/admin/operation', adminHealthSchema),
    ).rejects.toMatchObject({
      code: 'MALFORMED_API_RESPONSE',
      status: 200,
    });
  });

  it('maps explicit resources to server queries with validated pagination', async () => {
    const requestedUrls: string[] = [];
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async (input) => {
        requestedUrls.push(String(input));
        return new Response(
          JSON.stringify({
            data: {
              items: [
                {
                  id: '00000000-0000-4000-8000-000000000010',
                  sku: 'AISENLENS_PRO',
                  name: 'AisenLens Pro',
                  billingType: 'one_time',
                  status: 'active',
                  currentVersion: null,
                },
              ],
              page: { hasMore: false, nextCursor: null },
            },
            requestId,
          }),
          { headers: { 'content-type': 'application/json' }, status: 200 },
        );
      },
    });

    const provider = createAdminDataProvider(client);
    const result = await provider.getList('products', {
      limit: 10,
      search: 'Aisen Lens',
      status: 'active',
      sort: 'sku',
      direction: 'asc',
    });

    expect(result.data.items[0]?.sku).toBe('AISENLENS_PRO');
    const url = new URL(requestedUrls[0]);
    expect(url.pathname).toBe('/v1/admin/products');
    expect(Object.fromEntries(url.searchParams)).toEqual({
      limit: '10',
      search: 'Aisen Lens',
      status: 'active',
      sort: 'sku',
      direction: 'asc',
    });
  });

  it('maps getOne to an explicit resource path and rejects arbitrary resources or ids', async () => {
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async (input) =>
        new Response(
          JSON.stringify({
            data: {
              id: '00000000-0000-4000-8000-000000000010',
              sku: 'AISENLENS_PRO',
              name: 'AisenLens Pro',
              billingType: 'one_time',
              status: 'active',
              currentVersion: null,
            },
            requestId,
          }),
          { headers: { 'content-type': 'application/json' }, status: 200 },
        ),
    });
    const provider = createAdminDataProvider(client);

    await expect(
      provider.getOne('products', '00000000-0000-4000-8000-000000000010'),
    ).resolves.toMatchObject({ data: { sku: 'AISENLENS_PRO' } });
    await expect(provider.getOne('products', 'not-a-uuid')).rejects.toThrow(
      'Admin resource IDs must be UUIDs.',
    );
    await expect(provider.getList('arbitraryTable' as never)).rejects.toThrow(
      'Unsupported Admin resource: arbitraryTable',
    );
  });

  it('rejects malformed page metadata through the shared response contract', async () => {
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async () =>
        new Response(
          JSON.stringify({
            data: { items: [], page: { hasMore: true, nextCursor: '' } },
            requestId,
          }),
          { status: 200 },
        ),
    });
    const provider = createAdminDataProvider(client);

    await expect(provider.getList('products')).rejects.toMatchObject({
      code: 'MALFORMED_API_RESPONSE',
      status: 200,
    });
  });
});
