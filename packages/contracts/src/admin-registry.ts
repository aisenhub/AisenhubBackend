import { z } from 'zod';

export const PermissionActions = [
  'applications.read',
  'applications.change_production_origin',
  'application_memberships.read',
  'application_memberships.manage',
  'oauth_clients.read',
  'oauth_clients.manage',
  'products.read',
  'products.create',
  'product_versions.publish',
  'product_versions.retire',
  'product_versions.set_current',
  'redemption_batches.generate_codes',
  'redemption_batches.pause',
  'redemption_batches.close',
  'entitlements.grant',
  'entitlements.revoke',
  'entitlements.restore',
  'users.disable',
  'account_deletion.process',
  'orders.read',
  'orders.verify',
  'order_items.refund',
  'admin_members.manage',
  'audit_logs.read',
] as const;

export const PermissionActionSchema = z.enum(PermissionActions);
export type PermissionAction = (typeof PermissionActions)[number];

export const AdminRoles = ['owner', 'admin', 'support', 'finance'] as const;
export const AdminRoleSchema = z.enum(AdminRoles);
export type AdminRole = (typeof AdminRoles)[number];
