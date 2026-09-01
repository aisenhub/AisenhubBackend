import { describe, expect, it } from 'vitest';

import {
  AdminClientError,
  createAdminClient,
  createAdminDataProvider,
  createBusinessCommandClient,
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
      fetch: async () =>
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

  it('maps Catalog resources and Product overview to explicit backend endpoints', async () => {
    const requestedUrls: string[] = [];
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async (input) => {
        const url = String(input);
        requestedUrls.push(url);
        const payload = url.includes('/overview')
          ? {
              product: {
                id: '00000000-0000-4000-8000-000000000010',
                sku: 'AISENLENS_PRO',
                name: 'AisenLens Pro',
                billingType: 'one_time',
                status: 'active',
                currentVersion: null,
              },
              versions: [],
              prices: [],
              featureSnapshots: [],
              redemptionBatches: [],
              auditLogs: [],
            }
          : {
              items: [
                {
                  id: '00000000-0000-4000-8000-000000000011',
                  appId: '00000000-0000-4000-8000-000000000012',
                  appSlug: 'account',
                  environment: 'development',
                  origin: 'http://localhost:5173',
                  isActive: true,
                  createdAt: '2026-09-01T12:00:00.000Z',
                  updatedAt: '2026-09-01T12:00:00.000Z',
                },
              ],
              page: { hasMore: false, nextCursor: null },
            };
        return new Response(JSON.stringify({ data: payload, requestId }), {
          headers: { 'content-type': 'application/json' },
          status: 200,
        });
      },
    });
    const provider = createAdminDataProvider(client);

    await expect(
      provider.getList('origins', { search: 'localhost', sort: 'origin' }),
    ).resolves.toMatchObject({
      data: { items: [{ appSlug: 'account' }] },
    });
    await expect(
      provider.getProductOverview('00000000-0000-4000-8000-000000000010'),
    ).resolves.toMatchObject({ data: { product: { sku: 'AISENLENS_PRO' } } });
    expect(new URL(requestedUrls[0]).pathname).toBe('/v1/admin/origins');
    expect(new URL(requestedUrls[1]).pathname).toBe(
      '/v1/admin/products/00000000-0000-4000-8000-000000000010/overview',
    );
  });

  it('maps draft mutations to named endpoints with a stable idempotency key', async () => {
    let receivedUrl = '';
    let receivedInit: RequestInit | undefined;
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      csrfToken: () => 'csrf-token',
      fetch: async (input, init) => {
        receivedUrl = String(input);
        receivedInit = init;
        return new Response(
          JSON.stringify({
            data: {
              id: '00000000-0000-4000-8000-000000000010',
              slug: 'draft-app',
              name: 'Draft App',
              category: 'tool',
              status: 'draft',
              originCount: 0,
              createdAt: '2026-09-01T12:00:00.000Z',
              updatedAt: '2026-09-01T12:00:00.000Z',
            },
            requestId,
          }),
          { headers: { 'content-type': 'application/json' }, status: 201 },
        );
      },
    });
    const provider = createAdminDataProvider(client);

    await expect(
      provider.createApplication(
        { slug: 'draft-app', name: 'Draft App', category: 'tool', reason: 'catalog setup' },
        { idempotencyKey: 'draft-app-create-1' },
      ),
    ).resolves.toMatchObject({ data: { slug: 'draft-app' } });
    expect(new URL(receivedUrl).pathname).toBe('/v1/admin/applications');
    expect(receivedInit?.method).toBe('POST');
    expect(new Headers(receivedInit?.headers).get('idempotency-key')).toBe('draft-app-create-1');
    expect(new Headers(receivedInit?.headers).get('x-csrf-token')).toBe('csrf-token');
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

  it('validates and sends typed publish commands with invalidation metadata', async () => {
    const productVersionId = '00000000-0000-4000-8000-000000000010';
    let receivedUrl = '';
    let receivedBody = '';
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      csrfToken: () => 'csrf-memory-token',
      fetch: async (input, init) => {
        receivedUrl = String(input);
        receivedBody = String(init?.body);
        return new Response(
          JSON.stringify({
            data: {
              productVersionId,
              status: 'published',
              publishedAt: null,
              auditLogId: '00000000-0000-4000-8000-000000000012',
            },
            requestId,
          }),
          { headers: { 'content-type': 'application/json' }, status: 200 },
        );
      },
    });

    const commands = createBusinessCommandClient(client);
    const result = await commands.publishProductVersion(
      productVersionId,
      { reason: 'release local version', confirmation: true },
      { idempotencyKey: 'publish-local-001' },
    );

    expect(receivedUrl).toBe(
      `https://api.example.test/v1/admin/product-versions/${productVersionId}/publish`,
    );
    expect(JSON.parse(receivedBody)).toEqual({
      reason: 'release local version',
      confirmation: true,
    });
    expect(result.command).toEqual({
      idempotencyKey: 'publish-local-001',
      entity: { resource: 'productVersions', id: productVersionId },
      invalidates: ['products', 'productVersions'],
    });
  });

  it('retries a transport timeout with the same idempotency key and maps MFA errors', async () => {
    const batchId = '00000000-0000-4000-8000-000000000011';
    const keys: string[] = [];
    let attempts = 0;
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async (_input, init) => {
        attempts += 1;
        keys.push(new Headers(init?.headers).get('Idempotency-Key') ?? '');
        if (attempts === 1) throw new TypeError('network timeout');
        return new Response(
          JSON.stringify({
            data: {
              batchId,
              codes: [{ code: 'AH-LOCAL-ABCD-2345', codeHint: 'AH-****-2345' }],
            },
            requestId,
          }),
          { headers: { 'content-type': 'application/json' }, status: 200 },
        );
      },
    });
    const commands = createBusinessCommandClient(client);

    const result = await commands.generateRedemptionCodes(batchId, {
      reason: 'generate local codes',
      confirmation: true,
      quantity: 1,
    });
    expect(attempts).toBe(2);
    expect(keys[0]).toBeTruthy();
    expect(keys[1]).toBe(keys[0]);
    expect(result.command.invalidates).toEqual(['redemptionBatches', 'redemptionCodes']);

    const errorClient = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async () =>
        new Response(
          JSON.stringify({
            error: { code: 'MFA_REQUIRED', message: 'MFA is required.', requestId },
          }),
          { status: 403 },
        ),
    });
    await expect(
      createBusinessCommandClient(errorClient).pauseRedemptionBatch(batchId, {
        reason: 'pause local batch',
        confirmation: true,
      }),
    ).rejects.toMatchObject<Partial<AdminClientError>>({
      code: 'MFA_REQUIRED',
      requestId,
      status: 403,
    });
  });

  it('uses architecture-named routes for Set Current and production Origin commands', async () => {
    const productId = '00000000-0000-4000-8000-000000000013';
    const originId = '00000000-0000-4000-8000-000000000014';
    const paths: string[] = [];
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async (input) => {
        const url = new URL(String(input));
        paths.push(url.pathname);
        const data = url.pathname.includes('set-current-version')
          ? {
              productId,
              currentVersionId: '00000000-0000-4000-8000-000000000015',
              auditLogId: '00000000-0000-4000-8000-000000000016',
            }
          : {
              originId,
              applicationId: '00000000-0000-4000-8000-000000000017',
              appSlug: 'account',
              environment: 'production',
              origin: 'https://account.example.com',
              isActive: true,
              createdAt: '2026-09-01T12:00:00.000Z',
              updatedAt: '2026-09-01T12:00:00.000Z',
              auditLogId: '00000000-0000-4000-8000-000000000018',
            };
        return new Response(JSON.stringify({ data, requestId }), {
          headers: { 'content-type': 'application/json' },
          status: 200,
        });
      },
    });
    const commands = createBusinessCommandClient(client);

    await commands.setCurrentProductVersion(productId, {
      productVersionId: '00000000-0000-4000-8000-000000000015',
      reason: 'switch current version',
      confirmation: true,
    });
    await commands.changeProductionOrigin(originId, {
      appSlug: 'account',
      origin: 'https://account.example.com',
      reason: 'switch production host',
      confirmation: true,
    });

    expect(paths).toEqual([
      `/v1/admin/products/${productId}/set-current-version`,
      `/v1/admin/app-origins/${originId}/change-production-origin`,
    ]);
  });

  it('rejects missing command reason before transport and refuses non-UUID targets', async () => {
    let called = false;
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async () => {
        called = true;
        return new Response('{}', { status: 500 });
      },
    });
    const commands = createBusinessCommandClient(client);

    await expect(
      commands.retireProductVersion('00000000-0000-4000-8000-000000000010', {
        confirmation: true,
      } as never),
    ).rejects.toThrow();
    expect(() =>
      commands.closeRedemptionBatch('not-a-uuid', {
        reason: 'close',
        confirmation: true,
      }),
    ).toThrow('Admin command targets must be UUIDs.');
    expect(called).toBe(false);
  });
});
