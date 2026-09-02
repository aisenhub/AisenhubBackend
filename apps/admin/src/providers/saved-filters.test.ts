import { afterEach, describe, expect, it, vi } from 'vitest';

import { loadSavedFilters, saveCurrentFilter, savedFilterStorageKeyForTest } from './saved-filters';

const storage = new Map<string, string>();

vi.stubGlobal('localStorage', {
  getItem: (key: string) => storage.get(key) ?? null,
  setItem: (key: string, value: string) => storage.set(key, value),
  removeItem: (key: string) => storage.delete(key),
});

afterEach(() => storage.clear());

describe('Admin saved filters', () => {
  it('stores only resource-scoped allowlisted status values', () => {
    expect(saveCurrentFilter({ resource: 'orders', status: 'paid' })).toMatchObject({
      id: 'orders:paid',
      label: 'Status: paid',
    });
    expect(loadSavedFilters('orders')).toEqual([
      { id: 'orders:paid', resource: 'orders', status: 'paid', label: 'Status: paid' },
    ]);
    expect(savedFilterStorageKeyForTest('orders')).toBe('aisenhub.admin.saved-filters.v1.orders');
  });

  it('rejects invalid resources/statuses and never persists search or expression fields', () => {
    expect(saveCurrentFilter({ resource: 'orders', status: 'sql' })).toBeNull();
    expect(saveCurrentFilter({ resource: 'unknown', status: 'paid' })).toBeNull();
    expect(storage.size).toBe(0);
    storage.set(
      'aisenhub.admin.saved-filters.v1.orders',
      JSON.stringify([
        { resource: 'orders', status: 'paid', search: 'email@example.test', filter: '1=1' },
      ]),
    );
    expect(loadSavedFilters('orders')).toEqual([
      { id: 'orders:paid', resource: 'orders', status: 'paid', label: 'Status: paid' },
    ]);
    expect(JSON.stringify(loadSavedFilters('orders'))).not.toMatch(/email|search|filter|sql/i);
  });

  it('isolates resources and tolerates malformed local preferences', () => {
    saveCurrentFilter({ resource: 'orders', status: 'paid' });
    saveCurrentFilter({ resource: 'orders', status: 'chargeback' });
    expect(loadSavedFilters('users')).toEqual([]);
    storage.set('aisenhub.admin.saved-filters.v1.users', '{not-json');
    expect(loadSavedFilters('users')).toEqual([]);
  });
});
