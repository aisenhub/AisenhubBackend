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
  it('attaches bearer and idempotency headers without persistent storage', async () => {
    let receivedInit: RequestInit | undefined;
    const client = createAdminClient({
      baseUrl: 'https://api.example.test/',
      accessToken: () => 'access-token',
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
    expect(new Headers(receivedInit?.headers).get('authorization')).toBe('Bearer access-token');
    expect(receivedInit?.credentials).toBe('omit');
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

  it('exposes application membership and OAuth client operations through the Admin API boundary', async () => {
    const applicationId = '00000000-0000-4000-8000-000000000010';
    const membershipId = '00000000-0000-4000-8000-000000000011';
    const clientId = '00000000-0000-4000-8000-000000000012';
    const requested: string[] = [];
    const adminClient = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async (input) => {
        const url = String(input);
        requested.push(url);
        const isMembership = url.includes('/memberships');
        const isOAuth = url.includes('/oauth-clients');
        const data = url.endsWith('/memberships')
          ? {
              items: [
                {
                  id: membershipId,
                  applicationId,
                  applicationSlug: 'lens',
                  applicationName: 'Lens',
                  userId: applicationId,
                  status: 'active',
                  createdSource: 'admin',
                  joinedAt: '2026-09-01T00:00:00.000Z',
                  activatedAt: null,
                  suspendedAt: null,
                  suspendedReason: null,
                  leftAt: null,
                  deletedAt: null,
                },
              ],
            }
          : url.endsWith('/oauth-clients')
            ? {
                items: [
                  {
                    id: clientId,
                    applicationId,
                    provider: 'oidc',
                    externalClientId: 'lens-web',
                    clientType: 'public',
                    environment: 'development',
                    name: 'Lens Web',
                    status: 'active',
                    createdAt: '2026-09-01T00:00:00.000Z',
                    updatedAt: '2026-09-01T00:00:00.000Z',
                  },
                ],
              }
            : isMembership
              ? {
                  id: membershipId,
                  applicationId,
                  userId: applicationId,
                  status: 'suspended',
                  createdSource: 'admin',
                  joinedAt: '2026-09-01T00:00:00.000Z',
                  activatedAt: null,
                  suspendedAt: '2026-09-03T00:00:00.000Z',
                  leftAt: null,
                  deletedAt: null,
                  auditLogId: clientId,
                }
              : isOAuth
                ? {
                    id: clientId,
                    applicationId,
                    provider: 'oidc',
                    externalClientId: 'lens-web',
                    clientType: 'public',
                    environment: 'development',
                    name: 'Lens Web',
                    status: 'disabled',
                    createdAt: '2026-09-01T00:00:00.000Z',
                    updatedAt: '2026-09-03T00:00:00.000Z',
                    auditLogId: membershipId,
                  }
                : {};
        return new Response(JSON.stringify({ data, requestId }), {
          headers: { 'content-type': 'application/json' },
        });
      },
    });
    const provider = createAdminDataProvider(adminClient);
    await expect(provider.getApplicationMemberships(applicationId)).resolves.toBeTruthy();
    await expect(provider.getApplicationOAuthClients(applicationId)).resolves.toBeTruthy();
    const commands = createBusinessCommandClient(adminClient);
    await commands.suspendApplicationMembership(
      applicationId,
      membershipId,
      { reason: 'security review', confirmation: true },
      { idempotencyKey: 'membership-suspend-001' },
    );
    await commands.disableOAuthClient(
      applicationId,
      clientId,
      { reason: 'rotate client', confirmation: true },
      { idempotencyKey: 'oauth-disable-001' },
    );
    expect(requested).toEqual([
      `https://api.example.test/v1/admin/applications/${applicationId}/memberships`,
      `https://api.example.test/v1/admin/applications/${applicationId}/oauth-clients`,
      `https://api.example.test/v1/admin/applications/${applicationId}/memberships/${membershipId}/suspend`,
      `https://api.example.test/v1/admin/applications/${applicationId}/oauth-clients/${clientId}/disable`,
    ]);
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

  it('maps Customer deletion queries and User 360 to dedicated backend projections', async () => {
    const requestedUrls: string[] = [];
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async (input) => {
        const url = String(input);
        requestedUrls.push(url);
        const data = url.includes('/overview')
          ? {
              profile: {
                userId: '00000000-0000-4000-8000-000000000010',
                displayName: 'Overview User',
                avatarUrl: null,
                locale: 'en-US',
                status: 'active',
                createdAt: '2026-09-01T12:00:00.000Z',
                updatedAt: '2026-09-01T12:00:00.000Z',
              },
              adminRole: null,
              entitlements: [],
              redemptions: [],
              feedback: [],
              sessionSummary: { activeCount: 0, totalCount: 0, lastSeenAt: null },
              deletionRequests: [],
              auditTimeline: [],
            }
          : {
              items: [
                {
                  id: '00000000-0000-4000-8000-000000000011',
                  userId: '00000000-0000-4000-8000-000000000010',
                  status: 'pending',
                  executeAfter: '2026-09-01T12:00:00.000Z',
                  attemptCount: 0,
                  lastErrorCode: null,
                  nextAttemptAt: null,
                  requestedAt: '2026-09-01T12:00:00.000Z',
                  completedAt: null,
                  cancelledAt: null,
                },
              ],
              page: { hasMore: false, nextCursor: null },
            };
        return new Response(JSON.stringify({ data, requestId }), {
          headers: { 'content-type': 'application/json' },
        });
      },
    });
    const provider = createAdminDataProvider(client);

    await expect(provider.getList('accountDeletionRequests')).resolves.toMatchObject({
      data: { items: [{ status: 'pending' }] },
    });
    await expect(
      provider.getUserOverview('00000000-0000-4000-8000-000000000010'),
    ).resolves.toMatchObject({ data: { profile: { displayName: 'Overview User' } } });
    expect(new URL(requestedUrls[0]).pathname).toBe('/v1/admin/account-deletion-requests');
    expect(new URL(requestedUrls[1]).pathname).toBe(
      '/v1/admin/users/00000000-0000-4000-8000-000000000010/overview',
    );
  });

  it('maps Order 360 to one typed aggregate endpoint', async () => {
    const orderId = '00000000-0000-4000-8000-000000000031';
    let requestedUrl = '';
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async (input) => {
        requestedUrl = String(input);
        return new Response(
          JSON.stringify({
            data: {
              order: {
                id: orderId,
                orderNo: 'AH-ORDER-031',
                userId: null,
                customerRef: '00000000-0000-4000-8000-000000000032',
                status: 'cancelled',
                currency: 'USD',
                amountTotal: 0,
                channel: 'local',
                itemCount: 0,
                createdAt: '2026-09-01T12:00:00.000Z',
                paidAt: null,
                fulfilledAt: null,
                cancelledAt: '2026-09-01T12:00:00.000Z',
                refundedAt: null,
              },
              items: [],
              payments: [],
              events: [],
              refunds: [],
              exceptions: [],
              auditTimeline: [],
            },
            requestId,
          }),
          { headers: { 'content-type': 'application/json' }, status: 200 },
        );
      },
    });
    const provider = createAdminDataProvider(client);

    await expect(provider.getOrderOverview(orderId)).resolves.toMatchObject({
      data: { order: { orderNo: 'AH-ORDER-031' } },
    });
    expect(new URL(requestedUrl).pathname).toBe(`/v1/admin/orders/${orderId}/overview`);
  });

  it('maps draft mutations to named endpoints with a stable idempotency key', async () => {
    let receivedUrl = '';
    let receivedInit: RequestInit | undefined;
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      accessToken: () => 'access-token',
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
    expect(new Headers(receivedInit?.headers).get('authorization')).toBe('Bearer access-token');
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
      accessToken: () => 'access-token',
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
              codes: [
                {
                  codeId: '00000000-0000-4000-8000-000000000019',
                  code: 'AH-LOCAL-ABCD-2345',
                  codeHint: 'AH-****-2345',
                },
              ],
              auditLogId: '00000000-0000-4000-8000-000000000020',
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

  it('creates redemption batches and uses the architecture generate route', async () => {
    const batchId = '00000000-0000-4000-8000-000000000021';
    const paths: string[] = [];
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async (input) => {
        const url = new URL(String(input));
        paths.push(url.pathname);
        const data =
          url.pathname === '/v1/admin/redemption-batches'
            ? {
                id: batchId,
                name: 'Local codes',
                productSku: 'AISENLENS_PRO',
                productVersion: 1,
                status: 'draft',
                codePrefix: 'AH-LOCAL',
                quantity: 1,
                issuedCount: 0,
                redeemedCount: 0,
                startsAt: '2026-09-01T12:00:00.000Z',
                expiresAt: null,
                createdAt: '2026-09-01T12:00:00.000Z',
                auditLogId: '00000000-0000-4000-8000-000000000022',
              }
            : {
                batchId,
                codes: [
                  {
                    codeId: '00000000-0000-4000-8000-000000000023',
                    code: 'AH-LOCAL-ABCD-2345',
                    codeHint: 'AH-****-2345',
                  },
                ],
                auditLogId: '00000000-0000-4000-8000-000000000024',
              };
        return new Response(JSON.stringify({ data, requestId }), {
          headers: { 'content-type': 'application/json' },
          status: url.pathname === '/v1/admin/redemption-batches' ? 201 : 200,
        });
      },
    });
    const commands = createBusinessCommandClient(client);
    const created = await commands.createRedemptionBatch({
      name: 'Local codes',
      productId: '00000000-0000-4000-8000-000000000025',
      productVersionId: '00000000-0000-4000-8000-000000000026',
      codePrefix: 'AH-LOCAL',
      quantity: 1,
      source: 'manual',
      reason: 'create local batch',
      confirmation: true,
    });
    const generated = await commands.generateRedemptionCodes(batchId, {
      reason: 'generate local code',
      confirmation: true,
      quantity: 1,
    });
    expect(created.command.entity).toEqual({ resource: 'redemptionBatches', id: batchId });
    expect(generated.data.codes[0].code).toBe('AH-LOCAL-ABCD-2345');
    expect(paths).toEqual([
      '/v1/admin/redemption-batches',
      `/v1/admin/redemption-batches/${batchId}/generate`,
    ]);
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

  it('maps Customer commands to typed named routes and invalidation metadata', async () => {
    const userId = '00000000-0000-4000-8000-000000000031';
    const grantId = '00000000-0000-4000-8000-000000000032';
    const paths: string[] = [];
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async (input) => {
        const url = new URL(String(input));
        paths.push(url.pathname);
        const data = url.pathname.endsWith('/grant')
          ? {
              grantId,
              sourceId: '00000000-0000-4000-8000-000000000033',
              status: 'active',
              startsAt: '2026-09-01T12:00:00.000Z',
              expiresAt: null,
              auditLogId: '00000000-0000-4000-8000-000000000034',
            }
          : url.pathname.endsWith('/restore')
            ? {
                grantId: '00000000-0000-4000-8000-000000000035',
                sourceId: '00000000-0000-4000-8000-000000000036',
                status: 'active',
                startsAt: '2026-09-01T12:00:00.000Z',
                expiresAt: null,
                restoredGrantId: '00000000-0000-4000-8000-000000000035',
                restoresGrantId: grantId,
                auditLogId: '00000000-0000-4000-8000-000000000037',
              }
            : {
                userId,
                status: 'disabled',
                revokedSessionCount: 2,
                auditLogId: '00000000-0000-4000-8000-000000000038',
              };
        return new Response(JSON.stringify({ data, requestId }), {
          headers: { 'content-type': 'application/json' },
          status: 200,
        });
      },
    });
    const commands = createBusinessCommandClient(client);

    const granted = await commands.grantEntitlement(userId, {
      productVersionId: '00000000-0000-4000-8000-000000000039',
      reason: 'support grant',
      confirmation: true,
    });
    const restored = await commands.restoreEntitlement(grantId, {
      reason: 'restore entitlement',
      confirmation: true,
    });
    const disabled = await commands.disableUser(userId, {
      reason: 'disable account',
      confirmation: true,
    });

    expect(granted.data.sourceId).toBe('00000000-0000-4000-8000-000000000033');
    expect(restored.command.entity).toEqual({
      resource: 'entitlements',
      id: '00000000-0000-4000-8000-000000000035',
    });
    expect(disabled.data.revokedSessionCount).toBe(2);
    expect(paths).toEqual([
      `/v1/admin/users/${userId}/entitlements/grant`,
      `/v1/admin/entitlements/${grantId}/restore`,
      `/v1/admin/users/${userId}/disable`,
    ]);
  });

  it('maps manual order verification to its named command route and preserves retry metadata', async () => {
    const orderId = '00000000-0000-4000-8000-000000000041';
    let receivedUrl = '';
    let receivedBody = '';
    let receivedHeaders: Headers | undefined;
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      accessToken: () => 'access-token',
      fetch: async (input, init) => {
        receivedUrl = String(input);
        receivedBody = String(init?.body);
        receivedHeaders = new Headers(init?.headers);
        return new Response(
          JSON.stringify({
            data: {
              orderId,
              paymentId: '00000000-0000-4000-8000-000000000042',
              paymentEventId: '00000000-0000-4000-8000-000000000043',
              status: 'fulfilled',
              grantIds: ['00000000-0000-4000-8000-000000000044'],
              idempotent: false,
              auditLogId: '00000000-0000-4000-8000-000000000045',
              fulfillmentAuditLogId: '00000000-0000-4000-8000-000000000046',
              overviewPath: `/v1/admin/orders/${orderId}/overview`,
              auditPath: '/v1/admin/audit-logs/00000000-0000-4000-8000-000000000045',
            },
            requestId,
          }),
          { headers: { 'content-type': 'application/json' }, status: 200 },
        );
      },
    });
    const result = await createBusinessCommandClient(client).verifyOrder(
      orderId,
      {
        paymentReference: 'manual-proof-001',
        amountMinor: 2000,
        currency: 'USD',
        reason: 'verify cash receipt',
        confirmation: true,
      },
      { idempotencyKey: 'manual-verify-001' },
    );

    expect(receivedUrl).toBe(`https://api.example.test/v1/admin/orders/${orderId}/verify`);
    expect(JSON.parse(receivedBody)).toEqual({
      paymentReference: 'manual-proof-001',
      amountMinor: 2000,
      currency: 'USD',
      reason: 'verify cash receipt',
      confirmation: true,
    });
    expect(receivedHeaders?.get('Idempotency-Key')).toBe('manual-verify-001');
    expect(receivedHeaders?.get('authorization')).toBe('Bearer access-token');
    expect(result.command).toEqual({
      idempotencyKey: 'manual-verify-001',
      entity: { resource: 'orders', id: orderId },
      invalidates: ['orders', 'payments', 'entitlements', 'auditLogs'],
    });
  });

  it('maps OrderItem refunds to the named command route and invalidates commerce views', async () => {
    const itemId = '00000000-0000-4000-8000-000000000051';
    let receivedUrl = '';
    let receivedBody = '';
    let receivedHeaders: Headers | undefined;
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      accessToken: () => 'access-token',
      fetch: async (input, init) => {
        receivedUrl = String(input);
        receivedBody = String(init?.body);
        receivedHeaders = new Headers(init?.headers);
        return new Response(
          JSON.stringify({
            data: {
              itemId,
              orderId: '00000000-0000-4000-8000-000000000052',
              refundedAmount: 250,
              mode: 'compensation',
              orderStatus: 'partially_refunded',
              paymentStatus: 'partially_refunded',
              grantId: null,
              domainAuditLogId: '00000000-0000-4000-8000-000000000053',
              auditLogId: '00000000-0000-4000-8000-000000000054',
              idempotent: false,
              overviewPath: '/v1/admin/orders/00000000-0000-4000-8000-000000000052/overview',
              auditPath: '/v1/admin/audit-logs/00000000-0000-4000-8000-000000000054',
            },
            requestId,
          }),
          { headers: { 'content-type': 'application/json' }, status: 200 },
        );
      },
    });
    const result = await createBusinessCommandClient(client).refundOrderItem(
      itemId,
      { amountMinor: 250, mode: 'compensation', reason: 'service credit', confirmation: true },
      { idempotencyKey: 'refund-item-001' },
    );

    expect(receivedUrl).toBe(`https://api.example.test/v1/admin/order-items/${itemId}/refund`);
    expect(JSON.parse(receivedBody)).toEqual({
      amountMinor: 250,
      mode: 'compensation',
      reason: 'service credit',
      confirmation: true,
    });
    expect(receivedHeaders?.get('Idempotency-Key')).toBe('refund-item-001');
    expect(receivedHeaders?.get('authorization')).toBe('Bearer access-token');
    expect(result.command).toEqual({
      idempotencyKey: 'refund-item-001',
      entity: { resource: 'orders', id: itemId },
      invalidates: ['orders', 'payments', 'entitlements', 'auditLogs'],
    });
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
