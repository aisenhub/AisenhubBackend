import type {
  BaseRecord,
  CreateParams,
  DataProvider,
  GetListParams,
  GetOneParams,
  UpdateParams,
} from '@refinedev/core';

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
        'origin',
        'environment',
        'code',
        'version',
        'channel',
        'validFrom',
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

function recordVariables(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Admin draft variables must be an object.');
  }
  return { ...(value as Record<string, unknown>) };
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
    create: async <TData extends BaseRecord = BaseRecord, TVariables = Record<string, unknown>>(
      params: CreateParams<TVariables>,
    ) => {
      const variables = recordVariables(params.variables);
      let result;
      switch (params.resource) {
        case 'applications':
          result = await provider.createApplication(variables as never);
          break;
        case 'origins': {
          const applicationId = variables.applicationId;
          delete variables.applicationId;
          if (typeof applicationId !== 'string')
            throw new Error('applicationId is required for an Origin draft.');
          result = await provider.createOrigin(applicationId, variables as never);
          break;
        }
        case 'features':
          result = await provider.createFeature(variables as never);
          break;
        case 'products':
          result = await provider.createProduct(variables as never);
          break;
        case 'productVersions': {
          const productId = variables.productId;
          delete variables.productId;
          if (typeof productId !== 'string')
            throw new Error('productId is required for a Product Version draft.');
          result = await provider.createProductVersion(productId, variables as never);
          break;
        }
        case 'prices': {
          const productVersionId = variables.productVersionId;
          delete variables.productVersionId;
          if (typeof productVersionId !== 'string')
            throw new Error('productVersionId is required for a Price draft.');
          result = await provider.createPrice(productVersionId, variables as never);
          break;
        }
        default:
          return commandNotQuery('create');
      }
      return { data: result.data as unknown as TData };
    },
    update: async <TData extends BaseRecord = BaseRecord, TVariables = Record<string, unknown>>(
      params: UpdateParams<TVariables>,
    ) => {
      const variables = recordVariables(params.variables);
      const id = String(params.id);
      let result;
      switch (params.resource) {
        case 'applications':
          result = await provider.updateApplication(id, variables as never);
          break;
        case 'origins':
          result = await provider.updateOrigin(id, variables as never);
          break;
        case 'features':
          result = await provider.updateFeature(id, variables as never);
          break;
        case 'products':
          result = await provider.updateProduct(id, variables as never);
          break;
        case 'productVersions':
          result = await provider.updateProductVersion(id, variables as never);
          break;
        case 'prices':
          result = await provider.updatePrice(id, variables as never);
          break;
        default:
          return commandNotQuery('update');
      }
      return { data: result.data as unknown as TData };
    },
    deleteOne: async () => commandNotQuery('deleteOne'),
    getApiUrl: () => apiUrl,
  };
}
