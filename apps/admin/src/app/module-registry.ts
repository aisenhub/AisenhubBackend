import type { PermissionAction } from '@aisenhub/contracts';

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

export function getAdminModule(pathname: string): AdminModule | undefined {
  return adminModules.find((module) => pathname === module.path);
}
