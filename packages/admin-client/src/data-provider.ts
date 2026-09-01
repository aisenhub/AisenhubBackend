import {
  AdminCatalogListQuerySchema,
  AdminProductListResponseSchema,
  AdminProductSummarySchema,
  AdminProductVersionListResponseSchema,
  AdminProductVersionSummarySchema,
  AdminApplicationListResponseSchema,
  AdminApplicationSummarySchema,
  AdminAuditLogListResponseSchema,
  AdminAuditLogSummarySchema,
  AdminEntitlementListResponseSchema,
  AdminEntitlementSummarySchema,
  AdminFeedbackListResponseSchema,
  AdminFeedbackSummarySchema,
  AdminQueryListQuerySchema,
  AdminSystemHealthResponseSchema,
  AdminUserListResponseSchema,
  AdminUserSummarySchema,
  AdminRedemptionBatchListResponseSchema,
  AdminRedemptionBatchSummarySchema,
  AdminRedemptionCodeListResponseSchema,
  AdminRedemptionCodeSummarySchema,
  AdminRedemptionListResponseSchema,
  AdminRedemptionSummarySchema,
  type AdminApplicationSummary,
  type AdminAuditLogSummary,
  type AdminEntitlementSummary,
  type AdminFeedbackSummary,
  type AdminSystemHealthResponse,
  type AdminUserSummary,
  type AdminProductSummary,
  type AdminProductVersionSummary,
  type AdminRedemptionBatchSummary,
  type AdminRedemptionCodeSummary,
  type AdminRedemptionSummary,
  type ContractSchema,
  type PageMeta,
} from '@aisenhub/contracts';

import type { AdminClient, AdminResponse } from './index';

export const AdminResourceNames = [
  'applications',
  'users',
  'products',
  'productVersions',
  'redemptionBatches',
  'redemptionCodes',
  'redemptions',
  'entitlements',
  'feedback',
  'auditLogs',
] as const;

export type AdminResourceName = (typeof AdminResourceNames)[number];

export type AdminResourceItem = {
  applications: AdminApplicationSummary;
  users: AdminUserSummary;
  products: AdminProductSummary;
  productVersions: AdminProductVersionSummary;
  redemptionBatches: AdminRedemptionBatchSummary;
  redemptionCodes: AdminRedemptionCodeSummary;
  redemptions: AdminRedemptionSummary;
  entitlements: AdminEntitlementSummary;
  feedback: AdminFeedbackSummary;
  auditLogs: AdminAuditLogSummary;
};

export type AdminResourceQuery = {
  cursor?: string;
  limit?: number;
  search?: string;
  status?: string;
  sort?: string;
  direction?: 'asc' | 'desc';
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
    querySchema: AdminCatalogListQuerySchema,
  },
  redemptionBatches: {
    listPath: '/v1/admin/redemption-batches',
    itemPath: '/v1/admin/redemption-batches',
    listSchema: AdminRedemptionBatchListResponseSchema,
    itemSchema: AdminRedemptionBatchSummarySchema,
    querySchema: AdminCatalogListQuerySchema,
  },
  redemptionCodes: {
    listPath: '/v1/admin/redemption-codes',
    itemPath: '/v1/admin/redemption-codes',
    listSchema: AdminRedemptionCodeListResponseSchema,
    itemSchema: AdminRedemptionCodeSummarySchema,
    querySchema: AdminCatalogListQuerySchema,
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
  };
}
