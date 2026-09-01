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
  { key: 'growth', label: 'Growth', path: '/growth', available: false },
  { key: 'customers', label: 'Customers', path: '/customers', available: false },
  { key: 'platform', label: 'Platform', path: '/platform', available: false },
];

export function getAdminModule(pathname: string): AdminModule | undefined {
  return adminModules.find((module) => pathname === module.path);
}
