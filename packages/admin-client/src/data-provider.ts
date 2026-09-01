import {
  AdminCatalogListQuerySchema,
  AdminProductListResponseSchema,
  AdminProductSummarySchema,
  AdminProductVersionListResponseSchema,
  AdminProductVersionSummarySchema,
  AdminRedemptionBatchListResponseSchema,
  AdminRedemptionBatchSummarySchema,
  AdminRedemptionCodeListResponseSchema,
  AdminRedemptionCodeSummarySchema,
  AdminRedemptionListResponseSchema,
  AdminRedemptionSummarySchema,
  type AdminCatalogListQuery,
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
  'products',
  'productVersions',
  'redemptionBatches',
  'redemptionCodes',
  'redemptions',
] as const;

export type AdminResourceName = (typeof AdminResourceNames)[number];

export type AdminResourceItem = {
  products: AdminProductSummary;
  productVersions: AdminProductVersionSummary;
  redemptionBatches: AdminRedemptionBatchSummary;
  redemptionCodes: AdminRedemptionCodeSummary;
  redemptions: AdminRedemptionSummary;
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
};

const definitions: {
  readonly [R in AdminResourceName]: AdminResourceDefinition<R>;
} = {
  products: {
    listPath: '/v1/admin/products',
    itemPath: '/v1/admin/products',
    listSchema: AdminProductListResponseSchema,
    itemSchema: AdminProductSummarySchema,
  },
  productVersions: {
    listPath: '/v1/admin/product-versions',
    itemPath: '/v1/admin/product-versions',
    listSchema: AdminProductVersionListResponseSchema,
    itemSchema: AdminProductVersionSummarySchema,
  },
  redemptionBatches: {
    listPath: '/v1/admin/redemption-batches',
    itemPath: '/v1/admin/redemption-batches',
    listSchema: AdminRedemptionBatchListResponseSchema,
    itemSchema: AdminRedemptionBatchSummarySchema,
  },
  redemptionCodes: {
    listPath: '/v1/admin/redemption-codes',
    itemPath: '/v1/admin/redemption-codes',
    listSchema: AdminRedemptionCodeListResponseSchema,
    itemSchema: AdminRedemptionCodeSummarySchema,
  },
  redemptions: {
    listPath: '/v1/admin/redemptions',
    itemPath: '/v1/admin/redemptions',
    listSchema: AdminRedemptionListResponseSchema,
    itemSchema: AdminRedemptionSummarySchema,
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

function serializeQuery(query: AdminCatalogListQuery): string {
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
    query?: Partial<AdminCatalogListQuery>,
  ): Promise<AdminResponse<AdminListResult<R>>>;
  getOne<R extends AdminResourceName>(
    resource: R,
    id: string,
  ): Promise<AdminResponse<AdminResourceItem[R]>>;
}

export function createAdminDataProvider(client: AdminClient): AisenHubAdminDataProvider {
  return {
    async getList<R extends AdminResourceName>(
      resource: R,
      query: Partial<AdminCatalogListQuery> = {},
    ): Promise<AdminResponse<AdminListResult<R>>> {
      const definition = resourceDefinition(resource);
      const parsedQuery = AdminCatalogListQuerySchema.parse(query);
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
  };
}
