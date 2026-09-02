import type { PermissionAction } from '@aisenhub/contracts';
import type { ResourceProps } from '@refinedev/core';

export type AdminModule = {
  key: string;
  label: string;
  path: string;
  resource?: string;
  action?: PermissionAction;
  available: boolean;
};

export const adminModules: readonly AdminModule[] = [
  { key: 'overview', label: 'Overview', path: '/overview', available: true },
  {
    key: 'catalog',
    label: 'Catalog',
    path: '/catalog',
    resource: 'products',
    action: 'products.read',
    available: true,
  },
  {
    key: 'applications',
    label: 'Applications',
    path: '/applications',
    resource: 'applications',
    action: 'applications.read',
    available: true,
  },
  { key: 'users', label: 'Users', path: '/users', available: true },
  { key: 'feedback', label: 'Feedback', path: '/feedback', available: true },
  {
    key: 'orders',
    label: 'Commerce',
    path: '/orders',
    resource: 'orders',
    action: 'orders.read',
    available: true,
  },
  { key: 'redemptions', label: 'Redemptions', path: '/redemptions', available: true },
  {
    key: 'auditLogs',
    label: 'Audit logs',
    path: '/audit-logs',
    resource: 'auditLogs',
    action: 'audit_logs.read',
    available: true,
  },
  { key: 'systemHealth', label: 'System health', path: '/system-health', available: true },
  { key: 'growth', label: 'Growth', path: '/growth', available: false },
  { key: 'customers', label: 'Customers', path: '/customers', available: true },
  { key: 'platform', label: 'Platform', path: '/platform', available: false },
];

export const adminResources: ResourceProps[] = [
  { name: 'applications', list: '/applications' },
  { name: 'users', list: '/users' },
  { name: 'origins', list: '/catalog/origins' },
  { name: 'features', list: '/catalog/features' },
  { name: 'products', list: '/catalog/products' },
  { name: 'productVersions', list: '/catalog/product-versions' },
  { name: 'prices', list: '/catalog/prices' },
  { name: 'redemptionBatches', list: '/redemptions' },
  { name: 'redemptionCodes', list: '/redemption-codes' },
  { name: 'redemptions', list: '/redemption-receipts' },
  { name: 'entitlements', list: '/entitlements' },
  { name: 'feedback', list: '/feedback' },
  { name: 'auditLogs', list: '/audit-logs' },
  { name: 'accountDeletionRequests', list: '/account-deletion-requests' },
  { name: 'orders', list: '/orders' },
  { name: 'payments', list: '/payments' },
];

export function getAdminModule(pathname: string): AdminModule | undefined {
  return adminModules.find((module) => pathname === module.path);
}
