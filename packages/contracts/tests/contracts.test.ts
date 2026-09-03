import { describe, expect, it } from 'vitest';

import {
  AdminRoles,
  AdminActionMatrix,
  AdminCatalogListQuerySchema,
  AdminCatalogResourceQuerySchema,
  AdminChangeProductionOriginRequestSchema,
  AdminCreateRedemptionBatchRequestSchema,
  AdminCreateRedemptionBatchResponseSchema,
  AdminCreateApplicationRequestSchema,
  AdminCreateOriginRequestSchema,
  AdminCreatePriceRequestSchema,
  AdminCreateProductRequestSchema,
  AdminCreateProductVersionRequestSchema,
  AdminFeatureListResponseSchema,
  AdminApplicationListResponseSchema,
  AdminAuditLogListResponseSchema,
  AdminChargebackOrderRequestSchema,
  AdminEntitlementListResponseSchema,
  AdminFeedbackListResponseSchema,
  AdminOrderOverviewSchema,
  AdminRefundOrderItemRequestSchema,
  AdminRefundOrderItemResponseSchema,
  AdminSystemHealthResponseSchema,
  AdminUpdateApplicationRequestSchema,
  AdminUpdateProductRequestSchema,
  AdminOriginListResponseSchema,
  AdminPriceListResponseSchema,
  AdminProductOverviewSchema,
  AdminUserListResponseSchema,
  AdminVerifyOrderRequestSchema,
  AdminVerifyOrderResponseSchema,
  AdminGenerateRedemptionCodesRequestSchema,
  AdminProductListResponseSchema,
  AdminProductionOriginCommandResponseSchema,
  AdminPublishProductVersionRequestSchema,
  AdminRedemptionCodeSummarySchema,
  AdminSetCurrentProductVersionRequestSchema,
  AdminCurrentProductVersionCommandResponseSchema,
  AccessResponseSchema,
  ApplicationMembershipCommandRequestSchema,
  ApplicationMembershipSummarySchema,
  MyApplicationsResponseSchema,
  OAuthClientBindingSummarySchema,
  ApiErrorEnvelopeSchema,
  ApiSuccessEnvelopeSchema,
  EntitlementsResponseSchema,
  ErrorCodes,
  FeedbackRequestSchema,
  FeedbackResponseSchema,
  MeResponseSchema,
  PaginationQuerySchema,
  PermissionActions,
  PermissionActionSchema,
  evaluateAdminAction,
  PublicProductsResponseSchema,
  PaymentWebhookEventSchema,
  RedemptionRequestSchema,
  RedemptionResponseSchema,
  parseApiError,
} from '../src/index';

const requestId = '00000000-0000-4000-8000-000000000001';

describe('platform contract primitives', () => {
  it('requires requestId and validates the stable error envelope', () => {
    const parsed = ApiErrorEnvelopeSchema.parse({
      error: {
        code: ErrorCodes.REASON_REQUIRED,
        message: 'A reason is required.',
        requestId,
      },
    });

    expect(parsed.error.requestId).toBe(requestId);
    expect(() => parseApiError({ error: { code: ErrorCodes.REASON_REQUIRED } })).toThrow();
  });

  it('rejects invalid pagination and unknown permission actions', () => {
    expect(PaginationQuerySchema.parse({ limit: '10' }).limit).toBe(10);
    expect(() => PaginationQuerySchema.parse({ limit: 0 })).toThrow();
    expect(() => PermissionActionSchema.parse('orders.write')).toThrow();
  });

  it('keeps error codes, permission actions, and roles unique', () => {
    expect(new Set(Object.values(ErrorCodes)).size).toBe(Object.values(ErrorCodes).length);
    expect(new Set(PermissionActions).size).toBe(PermissionActions.length);
    expect(new Set(AdminRoles).size).toBe(AdminRoles.length);
  });

  it('keeps Commerce contracts item-oriented and excludes raw payment data', () => {
    expect(
      AdminVerifyOrderRequestSchema.parse({
        paymentReference: 'manual-proof-001',
        amountMinor: 2000,
        currency: 'USD',
        reason: 'verify manual payment',
        confirmation: true,
      }),
    ).toEqual({
      paymentReference: 'manual-proof-001',
      amountMinor: 2000,
      currency: 'USD',
      reason: 'verify manual payment',
      confirmation: true,
    });
    expect(() =>
      AdminVerifyOrderResponseSchema.parse({
        orderId: requestId,
        paymentId: '00000000-0000-4000-8000-000000000002',
        paymentEventId: '00000000-0000-4000-8000-000000000003',
        status: 'fulfilled',
        grantIds: ['00000000-0000-4000-8000-000000000004'],
        idempotent: false,
        auditLogId: '00000000-0000-4000-8000-000000000005',
        fulfillmentAuditLogId: '00000000-0000-4000-8000-000000000006',
        overviewPath: `/v1/admin/orders/${requestId}/overview`,
        auditPath: '/v1/admin/audit-logs/00000000-0000-4000-8000-000000000005',
      }),
    ).not.toThrow();
    expect(
      AdminRefundOrderItemRequestSchema.parse({
        amountMinor: 250,
        mode: 'compensation',
        reason: 'service credit',
        confirmation: true,
      }).mode,
    ).toBe('compensation');
    expect(
      AdminRefundOrderItemResponseSchema.parse({
        itemId: requestId,
        orderId: '00000000-0000-4000-8000-000000000007',
        refundedAmount: 250,
        mode: 'compensation',
        orderStatus: 'partially_refunded',
        paymentStatus: 'partially_refunded',
        grantId: null,
        domainAuditLogId: '00000000-0000-4000-8000-000000000008',
        auditLogId: '00000000-0000-4000-8000-000000000009',
        idempotent: false,
        overviewPath: '/v1/admin/orders/00000000-0000-4000-8000-000000000007/overview',
        auditPath: '/v1/admin/audit-logs/00000000-0000-4000-8000-000000000009',
      }).mode,
    ).toBe('compensation');
    expect(
      AdminChargebackOrderRequestSchema.parse({ reason: 'provider dispute', confirmation: true }),
    ).toEqual({ reason: 'provider dispute', confirmation: true });
    expect(
      PaymentWebhookEventSchema.parse({
        paymentId: requestId,
        orderId: '00000000-0000-4000-8000-000000000002',
        provider: 'manual',
        externalEventId: 'event-1',
        eventType: 'payment.succeeded',
        currency: 'USD',
        amount: 1000,
        occurredAt: '2026-09-01T12:00:00.000Z',
        payloadSummary: { providerStatus: 'approved' },
      }).eventType,
    ).toBe('payment.succeeded');
    expect(() =>
      AdminRefundOrderItemRequestSchema.parse({ amountMinor: 1, mode: 'return' }),
    ).toThrow();
    expect(() =>
      AdminVerifyOrderRequestSchema.parse({
        paymentReference: 'manual proof with spaces',
        amountMinor: 2000,
        currency: 'USD',
        reason: 'verify',
        confirmation: true,
      }),
    ).toThrow();
    expect(() =>
      PaymentWebhookEventSchema.parse({
        paymentId: requestId,
        orderId: requestId,
        provider: 'manual',
        externalEventId: 'event-2',
        eventType: 'payment.succeeded',
        currency: 'USD',
        amount: 1000,
        occurredAt: '2026-09-01T12:00:00.000Z',
        payloadSummary: { nested: { token: 'not-allowed' } },
      }),
    ).toThrow();
    expect(() =>
      AdminOrderOverviewSchema.parse({
        order: {},
        items: [],
        payments: [],
        events: [],
        rawEvent: {},
      }),
    ).toThrow();
  });

  it('preserves the success envelope serialization shape', () => {
    const schema = ApiSuccessEnvelopeSchema(PermissionActionSchema);
    const payload = schema.parse({ data: 'audit_logs.read', requestId });
    expect(JSON.stringify(payload)).toBe(
      '{"data":"audit_logs.read","requestId":"00000000-0000-4000-8000-000000000001"}',
    );
  });

  it('keeps the current profile identity contract strict', () => {
    const profile = {
      userId: requestId,
      displayName: 'Owner',
      avatarUrl: null,
      locale: 'zh-CN',
      status: 'active',
    };
    expect(MeResponseSchema.parse({ profile }).profile.userId).toBe(requestId);
    expect(() => MeResponseSchema.parse({ profile: { ...profile, deletedAt: null } })).toThrow();
  });

  it('validates the public catalog and product-facing command contracts', () => {
    expect(
      PublicProductsResponseSchema.parse({
        products: [
          { sku: 'AISENLENS_PRO', name: 'AisenLens Pro', billingType: 'one_time', version: 2 },
        ],
      }).products[0].version,
    ).toBe(2);
    expect(
      AccessResponseSchema.parse({
        allowed: true,
        feature: 'lens.export',
        value: { max: 10 },
        sourceProduct: 'AISENLENS_PRO',
        expiresAt: null,
        decisionId: requestId,
      }).allowed,
    ).toBe(true);
    expect(
      EntitlementsResponseSchema.parse({
        entitlements: [
          {
            feature: 'lens.export',
            value: { max: 10 },
            sourceProduct: 'AISENLENS_PRO',
            expiresAt: null,
          },
        ],
      }).entitlements,
    ).toHaveLength(1);
    expect(RedemptionRequestSchema.parse({ code: 'AH-PRO-ABCD-2345' }).code).toBe(
      'AH-PRO-ABCD-2345',
    );
    expect(
      RedemptionResponseSchema.parse({
        redemptionId: requestId,
        grantId: '00000000-0000-4000-8000-000000000002',
        status: 'redeemed',
      }).status,
    ).toBe('redeemed');
    expect(
      FeedbackResponseSchema.parse({
        id: requestId,
        status: 'open',
        createdAt: '2026-09-01T12:00:00.000Z',
      }).status,
    ).toBe('open');
    expect(() => FeedbackRequestSchema.parse({ kind: 'bug', title: '', content: 'x' })).toThrow();
    expect(() =>
      PublicProductsResponseSchema.parse({ products: [{ sku: 'X', price: 1 }] }),
    ).toThrow();
  });

  it('keeps application membership and OAuth projections safe and explicit', () => {
    const applicationId = '00000000-0000-4000-8000-000000000010';
    const membership = ApplicationMembershipSummarySchema.parse({
      id: requestId,
      application: {
        id: applicationId,
        slug: 'aisenlens',
        name: 'AisenLens',
        category: 'tool',
        status: 'active',
        registrationPolicy: 'open',
        membershipPolicy: 'create_on_first_authorization',
        defaultLocale: 'en-US',
      },
      userId: requestId,
      status: 'active',
      createdSource: 'oauth',
      joinedAt: '2026-09-03T00:00:00.000Z',
      activatedAt: '2026-09-03T00:00:00.000Z',
      suspendedAt: null,
      leftAt: null,
      deletedAt: null,
    });

    expect(
      MyApplicationsResponseSchema.parse({ applications: [membership] }).applications,
    ).toHaveLength(1);
    expect(
      ApplicationMembershipCommandRequestSchema.parse({
        action: 'suspend',
        membershipId: requestId,
        reason: 'policy review',
        idempotencyKey: 'membership-command-1',
      }).action,
    ).toBe('suspend');
    expect(
      OAuthClientBindingSummarySchema.parse({
        id: requestId,
        applicationId,
        provider: 'supabase',
        externalClientId: 'aisenlens-local-web',
        clientType: 'public',
        environment: 'development',
        name: 'AisenLens Local Web',
        status: 'active',
        createdAt: '2026-09-03T00:00:00.000Z',
        updatedAt: '2026-09-03T00:00:00.000Z',
      }).externalClientId,
    ).toBe('aisenlens-local-web');
    expect(() =>
      OAuthClientBindingSummarySchema.parse({
        id: requestId,
        applicationId,
        provider: 'supabase',
        externalClientId: 'secret-client',
        clientType: 'public',
        environment: 'development',
        name: 'Client',
        status: 'active',
        createdAt: '2026-09-03T00:00:00.000Z',
        updatedAt: '2026-09-03T00:00:00.000Z',
        clientSecret: 'must-not-cross-contract',
      }),
    ).toThrow();
  });

  it('keeps Admin catalog queries and dangerous commands explicit', () => {
    expect(AdminCatalogListQuerySchema.parse({ search: 'lens', status: 'active' })).toMatchObject({
      limit: 25,
      sort: 'createdAt',
      direction: 'desc',
    });
    expect(() => AdminCatalogListQuerySchema.parse({ sort: 'priceSql' })).toThrow();

    const product = AdminProductListResponseSchema.parse({
      items: [
        {
          id: requestId,
          sku: 'AISENLENS_PRO',
          name: 'AisenLens Pro',
          billingType: 'one_time',
          status: 'active',
          currentVersion: {
            id: '00000000-0000-4000-8000-000000000002',
            version: 2,
            status: 'published',
          },
        },
      ],
      page: { hasMore: false, nextCursor: null },
    });
    expect(product.items[0].currentVersion?.version).toBe(2);
    expect(() =>
      AdminRedemptionCodeSummarySchema.parse({
        id: requestId,
        batchId: requestId,
        codeHint: 'AH-****-2345',
        status: 'issued',
        redeemedAt: null,
        codeHash: 'secret',
      }),
    ).toThrow();

    expect(() => AdminPublishProductVersionRequestSchema.parse({ confirmation: true })).toThrow();
    expect(() => AdminGenerateRedemptionCodesRequestSchema.parse({ reason: 'test' })).toThrow();
    expect(
      AdminCreateRedemptionBatchRequestSchema.parse({
        name: 'Local codes',
        productId: requestId,
        productVersionId: '00000000-0000-4000-8000-000000000002',
        codePrefix: 'AH-LOCAL',
        quantity: 10,
        source: 'manual',
        reason: 'create test batch',
        confirmation: true,
      }).quantity,
    ).toBe(10);
    expect(() =>
      AdminCreateRedemptionBatchResponseSchema.parse({
        id: requestId,
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
        auditLogId: '00000000-0000-4000-8000-000000000004',
      }),
    ).not.toThrow();
    expect(
      AdminSetCurrentProductVersionRequestSchema.parse({
        reason: 'publish replacement',
        confirmation: true,
        productVersionId: '00000000-0000-4000-8000-000000000002',
      }).confirmation,
    ).toBe(true);
    expect(
      AdminChangeProductionOriginRequestSchema.parse({
        reason: 'switch production host',
        confirmation: true,
        appSlug: 'account',
        origin: 'https://account.example.com',
      }).appSlug,
    ).toBe('account');
    expect(() =>
      AdminChangeProductionOriginRequestSchema.parse({
        reason: 'switch production host',
        confirmation: true,
        appSlug: 'account',
        origin: 'https://account.example.com/path',
      }),
    ).toThrow();
    expect(
      AdminCurrentProductVersionCommandResponseSchema.parse({
        productId: requestId,
        currentVersionId: '00000000-0000-4000-8000-000000000002',
        auditLogId: '00000000-0000-4000-8000-000000000004',
      }).currentVersionId,
    ).toBe('00000000-0000-4000-8000-000000000002');
    expect(() =>
      AdminProductionOriginCommandResponseSchema.parse({
        originId: requestId,
        applicationId: requestId,
        appSlug: 'account',
        environment: 'production',
        origin: 'https://account.example.com',
        isActive: true,
        createdAt: '2026-09-01T12:00:00.000Z',
        updatedAt: '2026-09-01T12:00:00.000Z',
      }),
    ).toThrow();
  });

  it('validates Catalog and Product overview projections without secret fields', () => {
    expect(AdminCatalogResourceQuerySchema.parse({ sort: 'origin' }).sort).toBe('origin');
    expect(
      AdminOriginListResponseSchema.parse({
        items: [
          {
            id: requestId,
            appId: requestId,
            appSlug: 'account',
            environment: 'development',
            origin: 'http://localhost:5173',
            isActive: true,
            createdAt: '2026-09-01T12:00:00.000Z',
            updatedAt: '2026-09-01T12:00:00.000Z',
          },
        ],
        page: { hasMore: false, nextCursor: null },
      }).items[0].origin,
    ).toBe('http://localhost:5173');
    expect(AdminFeatureListResponseSchema.shape.items).toBeDefined();
    expect(AdminPriceListResponseSchema.shape.items).toBeDefined();
    expect(() => AdminProductOverviewSchema.parse({ product: {}, versions: [] })).toThrow();
  });

  it('keeps Catalog draft mutations explicit and rejects lifecycle fields', () => {
    expect(
      AdminCreateApplicationRequestSchema.parse({
        slug: 'draft-app',
        name: 'Draft App',
        category: 'tool',
        reason: 'catalog setup',
      }).slug,
    ).toBe('draft-app');
    expect(
      AdminCreateOriginRequestSchema.parse({
        environment: 'development',
        origin: 'http://localhost:5173',
        reason: 'catalog setup',
      }).origin,
    ).toBe('http://localhost:5173');
    expect(
      AdminCreateProductRequestSchema.parse({
        sku: 'DRAFT_PRODUCT',
        name: 'Draft Product',
        billingType: 'one_time',
        reason: 'catalog setup',
      }).billingType,
    ).toBe('one_time');
    expect(
      AdminCreateProductVersionRequestSchema.parse({ version: 1, reason: 'catalog setup' }).version,
    ).toBe(1);
    expect(
      AdminCreatePriceRequestSchema.parse({
        currency: 'USD',
        amountMinor: 100,
        channel: 'manual',
        reason: 'catalog setup',
      }).amountMinor,
    ).toBe(100);
    expect(
      AdminUpdateApplicationRequestSchema.parse({
        name: 'Updated',
        expectedUpdatedAt: '2026-09-01T12:00:00.000Z',
        reason: 'correct name',
      }).name,
    ).toBe('Updated');
    expect(() =>
      AdminCreateProductRequestSchema.parse({
        sku: 'DRAFT_PRODUCT',
        name: 'Draft Product',
        billingType: 'one_time',
        status: 'active',
        reason: 'invalid',
      }),
    ).toThrow();
    expect(() =>
      AdminUpdateProductRequestSchema.parse({
        status: 'active',
        expectedUpdatedAt: '2026-09-01T12:00:00.000Z',
        reason: 'invalid',
      }),
    ).toThrow();
  });

  it('validates read-only Admin operation projections and rejects leaked fields', () => {
    const page = { hasMore: false, nextCursor: null };
    expect(
      AdminApplicationListResponseSchema.parse({
        items: [
          {
            id: requestId,
            slug: 'admin',
            name: 'AisenHub Admin',
            category: 'platform',
            status: 'active',
            originCount: 1,
            createdAt: '2026-09-01T12:00:00.000Z',
            updatedAt: '2026-09-01T12:00:00.000Z',
          },
        ],
        page,
      }).items,
    ).toHaveLength(1);
    expect(
      AdminUserListResponseSchema.parse({
        items: [
          {
            id: requestId,
            displayName: null,
            status: 'active',
            adminRole: null,
            createdAt: '2026-09-01T12:00:00.000Z',
          },
        ],
        page,
      }).items[0].status,
    ).toBe('active');
    expect(() =>
      AdminFeedbackListResponseSchema.parse({
        items: [
          {
            id: requestId,
            appSlug: 'admin',
            userId: requestId,
            kind: 'bug',
            title: 'Issue',
            content: null,
            status: 'open',
            createdAt: '2026-09-01T12:00:00.000Z',
            password: 'never',
          },
        ],
        page,
      }),
    ).toThrow();
    expect(AdminEntitlementListResponseSchema.shape.items).toBeDefined();
    expect(AdminAuditLogListResponseSchema.shape.items).toBeDefined();
    expect(
      AdminSystemHealthResponseSchema.parse({
        status: 'healthy',
        checks: [{ name: 'database', status: 'healthy' }],
      }).status,
    ).toBe('healthy');
  });

  it('covers every fixed Admin role/action cell from one matrix source', () => {
    for (const role of AdminRoles) {
      for (const action of PermissionActions) {
        const decision = evaluateAdminAction(
          { role, status: 'active', aal: 'aal2', mfaState: 'verified' },
          action,
        );
        expect(decision.allowed).toBe(AdminActionMatrix[action].roles.includes(role));
      }
    }
  });

  it('denies unknown, inactive, and insufficient-assurance requests', () => {
    expect(evaluateAdminAction({ role: 'owner', status: 'active' }, 'admin.unknown').reason).toBe(
      'unknown_action',
    );
    expect(evaluateAdminAction({ role: 'owner', status: 'disabled' }, 'products.read').reason).toBe(
      'inactive_member',
    );
    expect(
      evaluateAdminAction(
        { role: 'finance', status: 'active', aal: 'aal1', mfaState: 'required' },
        'order_items.refund',
      ).reason,
    ).toBe('mfa_required');
  });

  it('keeps Support and Finance high-risk boundaries explicit', () => {
    const supportGrant = evaluateAdminAction(
      { role: 'support', status: 'active', aal: 'aal2', mfaState: 'verified' },
      'entitlements.grant',
    );
    expect(supportGrant).toMatchObject({ allowed: true, requiresMfa: true, requiresReason: true });

    const supportRestore = evaluateAdminAction(
      { role: 'support', status: 'active', aal: 'aal2', mfaState: 'verified' },
      'entitlements.restore',
    );
    expect(supportRestore.reason).toBe('role_denied');

    const financePublish = evaluateAdminAction(
      { role: 'finance', status: 'active', aal: 'aal2', mfaState: 'verified' },
      'product_versions.publish',
    );
    expect(financePublish.reason).toBe('role_denied');
  });
});
