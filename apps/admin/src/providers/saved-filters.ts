export const savedFilterResources = [
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

export type SavedFilterResource = (typeof savedFilterResources)[number];

const resourceStatuses: Readonly<Record<SavedFilterResource, readonly string[]>> = {
  applications: ['draft', 'active', 'suspended', 'retired'],
  users: ['active', 'disabled', 'deletion_pending', 'deleted'],
  origins: [],
  features: ['active', 'retired'],
  products: ['draft', 'active', 'archived'],
  productVersions: ['draft', 'published', 'retired'],
  prices: ['draft', 'active', 'retired'],
  redemptionBatches: ['draft', 'active', 'paused', 'closed'],
  redemptionCodes: ['issued', 'redeemed', 'revoked'],
  redemptions: ['redeemed'],
  entitlements: ['active', 'revoked'],
  feedback: ['open', 'in_progress', 'resolved', 'closed'],
  auditLogs: [],
  accountDeletionRequests: ['pending', 'processing', 'completed', 'failed', 'cancelled'],
  orders: [
    'pending',
    'paid',
    'fulfilled',
    'cancelled',
    'partially_refunded',
    'refunded',
    'chargeback',
  ],
  payments: ['pending', 'succeeded', 'partially_refunded', 'refunded', 'disputed', 'failed'],
};

export type SavedFilter = {
  readonly id: string;
  readonly resource: SavedFilterResource;
  readonly status?: string;
  readonly label: string;
};

type SavedFilterInput = {
  readonly resource: string;
  readonly status?: unknown;
};

function isSavedFilterResource(value: string): value is SavedFilterResource {
  return (savedFilterResources as readonly string[]).includes(value);
}

function isAllowedStatus(resource: SavedFilterResource, status: unknown): status is string {
  return typeof status === 'string' && resourceStatuses[resource].includes(status);
}

function storageKey(resource: SavedFilterResource): string {
  return `aisenhub.admin.saved-filters.v1.${resource}`;
}

function toSavedFilter(input: SavedFilterInput): SavedFilter | null {
  if (!isSavedFilterResource(input.resource)) return null;
  if (input.status !== undefined && !isAllowedStatus(input.resource, input.status)) return null;
  const status = input.status as string | undefined;
  return {
    id: `${input.resource}:${status ?? 'all'}`,
    resource: input.resource,
    ...(status ? { status } : {}),
    label: status ? `Status: ${status}` : 'All records',
  };
}

function localStorageOrNull(): Storage | null {
  try {
    return globalThis.localStorage ?? null;
  } catch {
    return null;
  }
}

export function loadSavedFilters(resource: string): readonly SavedFilter[] {
  if (!isSavedFilterResource(resource)) return [];
  const storage = localStorageOrNull();
  if (!storage) return [];
  try {
    const raw: unknown = JSON.parse(storage.getItem(storageKey(resource)) ?? '[]');
    if (!Array.isArray(raw)) return [];
    return raw
      .map((value) => {
        if (!value || typeof value !== 'object') return null;
        const record = value as Record<string, unknown>;
        return toSavedFilter({ resource, status: record.status });
      })
      .filter((value): value is SavedFilter => value !== null);
  } catch {
    return [];
  }
}

export function saveCurrentFilter(input: SavedFilterInput): SavedFilter | null {
  const filter = toSavedFilter(input);
  if (!filter) return null;
  const storage = localStorageOrNull();
  if (!storage) return filter;
  const existing = loadSavedFilters(filter.resource).filter((item) => item.id !== filter.id);
  try {
    storage.setItem(
      storageKey(filter.resource),
      JSON.stringify([filter, ...existing].slice(0, 20)),
    );
  } catch {
    // Local preferences are optional and must never block list operations.
  }
  return filter;
}

export function savedFilterStorageKeyForTest(resource: string): string | null {
  return isSavedFilterResource(resource) ? storageKey(resource) : null;
}
