import type { BaseRecord, DataProvider, GetListParams, GetOneParams } from '@refinedev/core';

import type {
  AisenHubAdminDataProvider,
  AdminResourceName,
  AdminResourceQuery,
} from '@aisenhub/admin-client';

function assertResource(resource: string): AdminResourceName {
  if (
    ![
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
    ].includes(resource)
  ) {
    throw new Error(`Unsupported Admin resource: ${resource}`);
  }
  return resource as AdminResourceName;
}

function queryFromRefine(params: GetListParams): Partial<AdminResourceQuery> {
  const query: Partial<AdminResourceQuery> = {};
  const pageSize = params.pagination?.pageSize;
  const currentPage = params.pagination?.currentPage;
  if (pageSize !== undefined) query.limit = pageSize;
  if (currentPage !== undefined && currentPage > 1) {
    throw new Error('Cursor pagination must be supplied by the Admin resource query.');
  }

  for (const sorter of params.sorters ?? []) {
    if (
      ![
        'createdAt',
        'updatedAt',
        'name',
        'slug',
        'sku',
        'status',
        'displayName',
        'title',
        'action',
        'targetType',
        'redeemedAt',
      ].includes(sorter.field)
    ) {
      throw new Error(`Unsupported Admin sort field: ${sorter.field}`);
    }
    query.sort = sorter.field;
    query.direction = sorter.order;
  }

  for (const filter of params.filters ?? []) {
    if (!('field' in filter) || !('operator' in filter) || !('value' in filter)) {
      throw new Error('Unsupported Admin filter shape.');
    }
    if (filter.operator !== 'eq' && filter.operator !== 'contains') {
      throw new Error(`Unsupported Admin filter operator: ${filter.operator}`);
    }
    if (filter.field === 'search' && typeof filter.value === 'string') {
      query.search = filter.value;
    } else if (filter.field === 'status' && typeof filter.value === 'string') {
      query.status = filter.value;
    } else {
      throw new Error(`Unsupported Admin filter field: ${filter.field}`);
    }
  }
  return query;
}

function commandNotQuery(operation: string): never {
  throw new Error(`${operation} is not a generic Admin data operation; use a Business Command.`);
}

export function createRefineDataProvider(
  provider: AisenHubAdminDataProvider,
  apiUrl: string,
): DataProvider {
  return {
    async getList<TData extends BaseRecord = BaseRecord>(params: GetListParams) {
      const result = await provider.getList(
        assertResource(params.resource),
        queryFromRefine(params),
      );
      return {
        data: result.data.items as unknown as TData[],
        total: result.data.items.length,
        page: result.data.page,
      };
    },
    async getOne<TData extends BaseRecord = BaseRecord>(params: GetOneParams) {
      const result = await provider.getOne(assertResource(params.resource), String(params.id));
      return { data: result.data as unknown as TData };
    },
    create: async () => commandNotQuery('create'),
    update: async () => commandNotQuery('update'),
    deleteOne: async () => commandNotQuery('deleteOne'),
    getApiUrl: () => apiUrl,
  };
}
