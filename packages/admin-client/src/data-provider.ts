import {
  AdminCatalogListQuerySchema,
  AdminCatalogResourceQuerySchema,
  AdminCreateApplicationRequestSchema,
  AdminCreateFeatureRequestSchema,
  AdminCreateOriginRequestSchema,
  AdminCreatePriceRequestSchema,
  AdminCreateProductRequestSchema,
  AdminCreateProductVersionRequestSchema,
  AdminFeatureListResponseSchema,
  AdminFeatureSummarySchema,
  AdminOriginListResponseSchema,
  AdminOriginSummarySchema,
  AdminPriceListResponseSchema,
  AdminPriceSummarySchema,
  AdminProductOverviewSchema,
  AdminProductListResponseSchema,
  AdminProductSummarySchema,
  AdminProductVersionListResponseSchema,
  AdminProductVersionSummarySchema,
  AdminApplicationListResponseSchema,
  AdminApplicationSummarySchema,
  AdminApplicationMembershipListResponseSchema,
  OAuthClientBindingListResponseSchema,
  AdminAuditLogListResponseSchema,
  AdminAuditLogSummarySchema,
  AdminAccountDeletionRequestListResponseSchema,
  AdminAccountDeletionRequestSummarySchema,
  AdminEntitlementListResponseSchema,
  AdminEntitlementSummarySchema,
  AdminFeedbackListResponseSchema,
  AdminFeedbackSummarySchema,
  AdminQueryListQuerySchema,
  AdminSystemHealthResponseSchema,
  AdminOverviewResponseSchema,
  AdminUserListResponseSchema,
  AdminUserSummarySchema,
  AdminUserOverviewSchema,
  AdminRedemptionBatchListResponseSchema,
  AdminRedemptionBatchSummarySchema,
  AdminRedemptionCodeListResponseSchema,
  AdminRedemptionCodeSummarySchema,
  AdminRedemptionListResponseSchema,
  AdminRedemptionSummarySchema,
  AdminUpdateApplicationRequestSchema,
  AdminUpdateFeatureRequestSchema,
  AdminUpdateOriginRequestSchema,
  AdminUpdatePriceRequestSchema,
  AdminUpdateProductRequestSchema,
  AdminUpdateProductVersionRequestSchema,
  AdminOrderListResponseSchema,
  AdminOrderOverviewSchema,
  AdminOrderSummarySchema,
  AdminPaymentListResponseSchema,
  PaymentSummarySchema,
  type AdminOrderSummary,
  type AdminOrderOverview,
  type PaymentSummary,
  type AdminApplicationSummary,
  type AdminApplicationMembershipListResponse,
  type OAuthClientBindingListResponse,
  type AdminCreateApplicationRequest,
  type AdminCreateFeatureRequest,
  type AdminCreateOriginRequest,
  type AdminCreatePriceRequest,
  type AdminCreateProductRequest,
  type AdminCreateProductVersionRequest,
  type AdminAuditLogSummary,
  type AdminAccountDeletionRequestSummary,
  type AdminEntitlementSummary,
  type AdminFeedbackSummary,
  type AdminFeatureSummary,
  type AdminOriginSummary,
  type AdminPriceSummary,
  type AdminProductOverview,
  type AdminSystemHealthResponse,
  type AdminOverviewResponse,
  type AdminUserSummary,
  type AdminUserOverview,
  type AdminProductSummary,
  type AdminProductVersionSummary,
  type AdminRedemptionBatchSummary,
  type AdminRedemptionCodeSummary,
  type AdminRedemptionSummary,
  type AdminUpdateApplicationRequest,
  type AdminUpdateFeatureRequest,
  type AdminUpdateOriginRequest,
  type AdminUpdatePriceRequest,
  type AdminUpdateProductRequest,
  type AdminUpdateProductVersionRequest,
  type ContractSchema,
  type PageMeta,
} from '@aisenhub/contracts';

import { withIdempotencyKey, type AdminClient, type AdminResponse } from './index';

export const AdminResourceNames = [
  'applications',
  'users',
  'origins',
  'features',
  'products',
  'productVersions',
  'prices',
  'redemptionBatches',
  'redemptionCodes',
  'redemptions',
  'entitlements',
  'feedback',
  'auditLogs',
  'accountDeletionRequests',
  'orders',
  'payments',
] as const;

export type AdminResourceName = (typeof AdminResourceNames)[number];

export type AdminResourceItem = {
  applications: AdminApplicationSummary;
  users: AdminUserSummary;
  origins: AdminOriginSummary;
  features: AdminFeatureSummary;
  products: AdminProductSummary;
  productVersions: AdminProductVersionSummary;
  prices: AdminPriceSummary;
  redemptionBatches: AdminRedemptionBatchSummary;
  redemptionCodes: AdminRedemptionCodeSummary;
  redemptions: AdminRedemptionSummary;
  entitlements: AdminEntitlementSummary;
  feedback: AdminFeedbackSummary;
  auditLogs: AdminAuditLogSummary;
  accountDeletionRequests: AdminAccountDeletionRequestSummary;
  orders: AdminOrderSummary;
  payments: PaymentSummary;
};

export type AdminResourceQuery = {
  applicationId?: string;
  cursor?: string;
  limit?: number;
  search?: string;
  status?: string;
  sort?: string;
  direction?: 'asc' | 'desc';
};

export type AdminDraftMutationOptions = {
  readonly idempotencyKey?: string;
  readonly maxAttempts?: 1 | 2;
  readonly signal?: AbortSignal;
};

export type AdminListResult<R extends AdminResourceName> = {
  items: AdminResourceItem[R][];
  page: PageMeta;
};

type AdminResourceDefinition<R extends AdminResourceName> = {
  readonly listPath: string;
  readonly itemPath: string;
  readonly listSchema: ContractSchema<AdminListResult<R>>;
  readonly itemSchema: ContractSchema<AdminResourceItem[R]>;
  readonly querySchema: ContractSchema<AdminResourceQuery>;
};

const definitions: {
  readonly [R in AdminResourceName]: AdminResourceDefinition<R>;
} = {
  applications: {
    listPath: '/v1/admin/applications',
    itemPath: '/v1/admin/applications',
    listSchema: AdminApplicationListResponseSchema,
    itemSchema: AdminApplicationSummarySchema,
    querySchema: AdminQueryListQuerySchema,
  },
  users: {
    listPath: '/v1/admin/users',
    itemPath: '/v1/admin/users',
    listSchema: AdminUserListResponseSchema,
    itemSchema: AdminUserSummarySchema,
    querySchema: AdminQueryListQuerySchema,
  },
  products: {
    listPath: '/v1/admin/products',
    itemPath: '/v1/admin/products',
    listSchema: AdminProductListResponseSchema,
    itemSchema: AdminProductSummarySchema,
    querySchema: AdminCatalogListQuerySchema,
  },
  productVersions: {
    listPath: '/v1/admin/product-versions',
    itemPath: '/v1/admin/product-versions',
    listSchema: AdminProductVersionListResponseSchema,
    itemSchema: AdminProductVersionSummarySchema,
    querySchema: AdminCatalogResourceQuerySchema,
  },
  origins: {
    listPath: '/v1/admin/origins',
    itemPath: '/v1/admin/origins',
    listSchema: AdminOriginListResponseSchema,
    itemSchema: AdminOriginSummarySchema,
    querySchema: AdminCatalogResourceQuerySchema,
  },
  features: {
    listPath: '/v1/admin/features',
    itemPath: '/v1/admin/features',
    listSchema: AdminFeatureListResponseSchema,
    itemSchema: AdminFeatureSummarySchema,
    querySchema: AdminCatalogResourceQuerySchema,
  },
  redemptionBatches: {
    listPath: '/v1/admin/redemption-batches',
    itemPath: '/v1/admin/redemption-batches',
    listSchema: AdminRedemptionBatchListResponseSchema,
    itemSchema: AdminRedemptionBatchSummarySchema,
    querySchema: AdminCatalogResourceQuerySchema,
  },
  redemptionCodes: {
    listPath: '/v1/admin/redemption-codes',
    itemPath: '/v1/admin/redemption-codes',
    listSchema: AdminRedemptionCodeListResponseSchema,
    itemSchema: AdminRedemptionCodeSummarySchema,
    querySchema: AdminCatalogResourceQuerySchema,
  },
  prices: {
    listPath: '/v1/admin/prices',
    itemPath: '/v1/admin/prices',
    listSchema: AdminPriceListResponseSchema,
    itemSchema: AdminPriceSummarySchema,
    querySchema: AdminCatalogResourceQuerySchema,
  },
  redemptions: {
    listPath: '/v1/admin/redemptions',
    itemPath: '/v1/admin/redemptions',
    listSchema: AdminRedemptionListResponseSchema,
    itemSchema: AdminRedemptionSummarySchema,
    querySchema: AdminQueryListQuerySchema,
  },
  entitlements: {
    listPath: '/v1/admin/entitlements',
    itemPath: '/v1/admin/entitlements',
    listSchema: AdminEntitlementListResponseSchema,
    itemSchema: AdminEntitlementSummarySchema,
    querySchema: AdminQueryListQuerySchema,
  },
  feedback: {
    listPath: '/v1/admin/feedback',
    itemPath: '/v1/admin/feedback',
    listSchema: AdminFeedbackListResponseSchema,
    itemSchema: AdminFeedbackSummarySchema,
    querySchema: AdminQueryListQuerySchema,
  },
  auditLogs: {
    listPath: '/v1/admin/audit-logs',
    itemPath: '/v1/admin/audit-logs',
    listSchema: AdminAuditLogListResponseSchema,
    itemSchema: AdminAuditLogSummarySchema,
    querySchema: AdminQueryListQuerySchema,
  },
  accountDeletionRequests: {
    listPath: '/v1/admin/account-deletion-requests',
    itemPath: '/v1/admin/account-deletion-requests',
    listSchema: AdminAccountDeletionRequestListResponseSchema,
    itemSchema: AdminAccountDeletionRequestSummarySchema,
    querySchema: AdminQueryListQuerySchema,
  },
  orders: {
    listPath: '/v1/admin/orders',
    itemPath: '/v1/admin/orders',
    listSchema: AdminOrderListResponseSchema,
    itemSchema: AdminOrderSummarySchema,
    querySchema: AdminQueryListQuerySchema,
  },
  payments: {
    listPath: '/v1/admin/payments',
    itemPath: '/v1/admin/payments',
    listSchema: AdminPaymentListResponseSchema,
    itemSchema: PaymentSummarySchema,
    querySchema: AdminQueryListQuerySchema,
  },
};

function resourceDefinition<R extends AdminResourceName>(resource: R): AdminResourceDefinition<R> {
  const definition = definitions[resource];
  if (!definition) throw new Error(`Unsupported Admin resource: ${String(resource)}`);
  return definition;
}

function encodeResourceId(id: string): string {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    throw new Error('Admin resource IDs must be UUIDs.');
  }
  return encodeURIComponent(id);
}

function serializeQuery(query: AdminResourceQuery): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined) params.set(key, String(value));
  }
  const search = params.toString();
  return search ? `?${search}` : '';
}

function draftIdempotencyKey(input?: string): string {
  const key = input?.trim() || globalThis.crypto?.randomUUID();
  if (!key) throw new Error('An Idempotency-Key is required.');
  return key;
}

function retryableDraftTransportError(error: unknown): boolean {
  if (error instanceof TypeError) return true;
  return Boolean(
    error &&
    typeof error === 'object' &&
    'name' in error &&
    ['TimeoutError', 'NetworkError'].includes(String(error.name)),
  );
}

async function runDraftMutation<TInput, TOutput>(
  client: AdminClient,
  path: string,
  method: 'POST' | 'PATCH',
  input: TInput,
  inputSchema: ContractSchema<TInput>,
  outputSchema: ContractSchema<TOutput>,
  options?: AdminDraftMutationOptions,
): Promise<AdminResponse<TOutput>> {
  const validated = inputSchema.parse(input);
  const idempotencyKey = draftIdempotencyKey(options?.idempotencyKey);
  const init = withIdempotencyKey(
    {
      method,
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(validated),
      signal: options?.signal,
    },
    idempotencyKey,
  );
  const maxAttempts = options?.maxAttempts ?? 2;
  let attempt = 0;
  while (true) {
    try {
      return await client.request(path, outputSchema, init);
    } catch (error) {
      attempt += 1;
      if (attempt >= maxAttempts || !retryableDraftTransportError(error)) throw error;
    }
  }
}

export interface AisenHubAdminDataProvider {
  getList<R extends AdminResourceName>(
    resource: R,
    query?: Partial<AdminResourceQuery>,
  ): Promise<AdminResponse<AdminListResult<R>>>;
  getOne<R extends AdminResourceName>(
    resource: R,
    id: string,
  ): Promise<AdminResponse<AdminResourceItem[R]>>;
  getSystemHealth(): Promise<AdminResponse<AdminSystemHealthResponse>>;
  getOverview(): Promise<AdminResponse<AdminOverviewResponse>>;
  getProductOverview(id: string): Promise<AdminResponse<AdminProductOverview>>;
  getUserOverview(id: string): Promise<AdminResponse<AdminUserOverview>>;
  getOrderOverview(id: string): Promise<AdminResponse<AdminOrderOverview>>;
  getApplicationMemberships(
    applicationId: string,
  ): Promise<AdminResponse<AdminApplicationMembershipListResponse>>;
  getApplicationOAuthClients(
    applicationId: string,
  ): Promise<AdminResponse<OAuthClientBindingListResponse>>;
  createApplication(
    input: AdminCreateApplicationRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminApplicationSummary>>;
  updateApplication(
    id: string,
    input: AdminUpdateApplicationRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminApplicationSummary>>;
  createOrigin(
    applicationId: string,
    input: AdminCreateOriginRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminOriginSummary>>;
  updateOrigin(
    id: string,
    input: AdminUpdateOriginRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminOriginSummary>>;
  createFeature(
    input: AdminCreateFeatureRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminFeatureSummary>>;
  updateFeature(
    id: string,
    input: AdminUpdateFeatureRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminFeatureSummary>>;
  createProduct(
    input: AdminCreateProductRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminProductSummary>>;
  updateProduct(
    id: string,
    input: AdminUpdateProductRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminProductSummary>>;
  createProductVersion(
    productId: string,
    input: AdminCreateProductVersionRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminProductVersionSummary>>;
  updateProductVersion(
    id: string,
    input: AdminUpdateProductVersionRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminProductVersionSummary>>;
  createPrice(
    productVersionId: string,
    input: AdminCreatePriceRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminPriceSummary>>;
  updatePrice(
    id: string,
    input: AdminUpdatePriceRequest,
    options?: AdminDraftMutationOptions,
  ): Promise<AdminResponse<AdminPriceSummary>>;
}

export function createAdminDataProvider(client: AdminClient): AisenHubAdminDataProvider {
  return {
    async getList<R extends AdminResourceName>(
      resource: R,
      query: Partial<AdminResourceQuery> = {},
    ): Promise<AdminResponse<AdminListResult<R>>> {
      const definition = resourceDefinition(resource);
      const parsedQuery = definition.querySchema.parse(query);
      return client.request(
        `${definition.listPath}${serializeQuery(parsedQuery)}`,
        definition.listSchema,
      );
    },

    async getOne<R extends AdminResourceName>(
      resource: R,
      id: string,
    ): Promise<AdminResponse<AdminResourceItem[R]>> {
      const definition = resourceDefinition(resource);
      return client.request(
        `${definition.itemPath}/${encodeResourceId(id)}`,
        definition.itemSchema,
      );
    },

    async getSystemHealth(): Promise<AdminResponse<AdminSystemHealthResponse>> {
      return client.request('/v1/admin/system-health', AdminSystemHealthResponseSchema);
    },

    async getOverview(): Promise<AdminResponse<AdminOverviewResponse>> {
      return client.request('/v1/admin/overview', AdminOverviewResponseSchema);
    },

    async getProductOverview(id: string): Promise<AdminResponse<AdminProductOverview>> {
      return client.request(
        `/v1/admin/products/${encodeResourceId(id)}/overview`,
        AdminProductOverviewSchema,
      );
    },

    async getUserOverview(id: string): Promise<AdminResponse<AdminUserOverview>> {
      return client.request(
        `/v1/admin/users/${encodeResourceId(id)}/overview`,
        AdminUserOverviewSchema,
      );
    },

    async getOrderOverview(id: string): Promise<AdminResponse<AdminOrderOverview>> {
      return client.request(
        `/v1/admin/orders/${encodeResourceId(id)}/overview`,
        AdminOrderOverviewSchema,
      );
    },

    async getApplicationMemberships(
      applicationId: string,
    ): Promise<AdminResponse<AdminApplicationMembershipListResponse>> {
      return client.request(
        `/v1/admin/applications/${encodeResourceId(applicationId)}/memberships`,
        AdminApplicationMembershipListResponseSchema,
      );
    },

    async getApplicationOAuthClients(
      applicationId: string,
    ): Promise<AdminResponse<OAuthClientBindingListResponse>> {
      return client.request(
        `/v1/admin/applications/${encodeResourceId(applicationId)}/oauth-clients`,
        OAuthClientBindingListResponseSchema,
      );
    },

    createApplication(input, options) {
      return runDraftMutation(
        client,
        '/v1/admin/applications',
        'POST',
        input,
        AdminCreateApplicationRequestSchema,
        AdminApplicationSummarySchema,
        options,
      );
    },
    updateApplication(id, input, options) {
      return runDraftMutation(
        client,
        `/v1/admin/applications/${encodeResourceId(id)}`,
        'PATCH',
        input,
        AdminUpdateApplicationRequestSchema,
        AdminApplicationSummarySchema,
        options,
      );
    },
    createOrigin(applicationId, input, options) {
      return runDraftMutation(
        client,
        `/v1/admin/applications/${encodeResourceId(applicationId)}/origins`,
        'POST',
        input,
        AdminCreateOriginRequestSchema,
        AdminOriginSummarySchema,
        options,
      );
    },
    updateOrigin(id, input, options) {
      return runDraftMutation(
        client,
        `/v1/admin/origins/${encodeResourceId(id)}`,
        'PATCH',
        input,
        AdminUpdateOriginRequestSchema,
        AdminOriginSummarySchema,
        options,
      );
    },
    createFeature(input, options) {
      return runDraftMutation(
        client,
        '/v1/admin/features',
        'POST',
        input,
        AdminCreateFeatureRequestSchema,
        AdminFeatureSummarySchema,
        options,
      );
    },
    updateFeature(id, input, options) {
      return runDraftMutation(
        client,
        `/v1/admin/features/${encodeResourceId(id)}`,
        'PATCH',
        input,
        AdminUpdateFeatureRequestSchema,
        AdminFeatureSummarySchema,
        options,
      );
    },
    createProduct(input, options) {
      return runDraftMutation(
        client,
        '/v1/admin/products',
        'POST',
        input,
        AdminCreateProductRequestSchema,
        AdminProductSummarySchema,
        options,
      );
    },
    updateProduct(id, input, options) {
      return runDraftMutation(
        client,
        `/v1/admin/products/${encodeResourceId(id)}`,
        'PATCH',
        input,
        AdminUpdateProductRequestSchema,
        AdminProductSummarySchema,
        options,
      );
    },
    createProductVersion(productId, input, options) {
      return runDraftMutation(
        client,
        `/v1/admin/products/${encodeResourceId(productId)}/versions`,
        'POST',
        input,
        AdminCreateProductVersionRequestSchema,
        AdminProductVersionSummarySchema,
        options,
      );
    },
    updateProductVersion(id, input, options) {
      return runDraftMutation(
        client,
        `/v1/admin/product-versions/${encodeResourceId(id)}`,
        'PATCH',
        input,
        AdminUpdateProductVersionRequestSchema,
        AdminProductVersionSummarySchema,
        options,
      );
    },
    createPrice(productVersionId, input, options) {
      return runDraftMutation(
        client,
        `/v1/admin/product-versions/${encodeResourceId(productVersionId)}/prices`,
        'POST',
        input,
        AdminCreatePriceRequestSchema,
        AdminPriceSummarySchema,
        options,
      );
    },
    updatePrice(id, input, options) {
      return runDraftMutation(
        client,
        `/v1/admin/prices/${encodeResourceId(id)}`,
        'PATCH',
        input,
        AdminUpdatePriceRequestSchema,
        AdminPriceSummarySchema,
        options,
      );
    },
  };
}
