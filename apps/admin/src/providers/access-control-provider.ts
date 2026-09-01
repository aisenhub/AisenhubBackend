import type { AccessControlProvider } from '@refinedev/core';
import {
  PermissionActionSchema,
  evaluateAdminAction,
  type AdminSessionResponse,
  type PermissionAction,
} from '@aisenhub/contracts';

const resourceActions: Readonly<Record<string, PermissionAction>> = {
  'products:list': 'products.read',
  'products:show': 'products.read',
  'products:create': 'products.create',
  'productVersions:list': 'products.read',
  'productVersions:show': 'products.read',
  'productVersions:publish': 'product_versions.publish',
  'productVersions:retire': 'product_versions.retire',
  'productVersions:setCurrent': 'product_versions.set_current',
};

function resolveAction(resource: string | undefined, action: string): PermissionAction | null {
  const direct = PermissionActionSchema.safeParse(action);
  if (direct.success) return direct.data;
  return resourceActions[`${resource ?? ''}:${action}`] ?? null;
}

export type AdminAccessControlOptions = {
  getSession: () => AdminSessionResponse | null;
};

export function createAdminAccessControlProvider(
  options: AdminAccessControlOptions,
): AccessControlProvider {
  return {
    can: async ({ resource, action }) => {
      const permission = resolveAction(resource, action);
      if (!permission) return { can: false, reason: 'Unknown Admin resource or action.' };

      const session = options.getSession();
      if (!session) return { can: false, reason: 'Admin session is required.' };

      const decision = evaluateAdminAction(
        {
          role: session.role,
          status: 'active',
          aal: session.aal,
          mfaState: session.mfaState,
        },
        permission,
      );
      return { can: decision.allowed, reason: decision.reason };
    },
  };
}
