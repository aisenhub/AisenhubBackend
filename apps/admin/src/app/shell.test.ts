import { describe, expect, it } from 'vitest';

import { getAdminErrorNotification } from './error-messages';
import { adminModules, getAdminModule } from './module-registry';

describe('Admin module registry', () => {
  it('keeps routes explicit and marks unfinished modules unavailable', () => {
    expect(adminModules.map((module) => module.path)).toEqual([
      '/overview',
      '/catalog',
      '/applications',
      '/users',
      '/audit-logs',
      '/system-health',
      '/growth',
      '/customers',
      '/platform',
    ]);
    expect(new Set(adminModules.map((module) => module.path)).size).toBe(adminModules.length);
    expect(getAdminModule('/catalog')?.action).toBe('products.read');
    expect(getAdminModule('/growth')?.available).toBe(false);
    expect(getAdminModule('/not-registered')).toBeUndefined();
  });
});

describe('Admin error notifications', () => {
  it('maps stable HTTP and contract failures to safe operator messages', () => {
    expect(getAdminErrorNotification({ status: 401 }).message).toBe('Session expired');
    expect(getAdminErrorNotification({ status: 403 }).message).toBe('Permission denied');
    expect(getAdminErrorNotification({ code: 'MFA_REQUIRED' }).message).toBe(
      'Authentication elevation required',
    );
    expect(getAdminErrorNotification({ status: 409 }).message).toBe('State conflict');
    expect(getAdminErrorNotification({ status: 422 }).message).toBe('Validation error');
    expect(getAdminErrorNotification({ status: 429 }).message).toBe('Too many requests');
    expect(getAdminErrorNotification({ status: 500 }).description).not.toMatch(/SQL|stack|table/i);
  });
});
