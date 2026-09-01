import matrix from './admin-permissions.matrix.json';

import {
  AdminRoles,
  PermissionActions,
  type AdminRole,
  type PermissionAction,
} from './admin-registry';

type RawAdminActionPolicy = {
  readonly roles: readonly AdminRole[];
  readonly requiresMfa: boolean;
  readonly reasonRoles: readonly AdminRole[];
};

export type AdminActionPolicy = RawAdminActionPolicy;

const actionMatrix = matrix.actions as Record<PermissionAction, RawAdminActionPolicy>;

if (
  PermissionActions.some((action) => !actionMatrix[action]) ||
  Object.keys(actionMatrix).length !== PermissionActions.length
) {
  throw new Error('Admin permission matrix must cover every approved action exactly once.');
}

export const AdminActionMatrix: Readonly<Record<PermissionAction, AdminActionPolicy>> =
  actionMatrix;

export type AdminAuthorizationContext = {
  readonly role: unknown;
  readonly status?: unknown;
  readonly aal?: unknown;
  readonly mfaState?: unknown;
};

export type AdminAuthorizationDecision = {
  readonly allowed: boolean;
  readonly reason:
    | 'allowed'
    | 'unknown_action'
    | 'unknown_role'
    | 'inactive_member'
    | 'role_denied'
    | 'mfa_required';
  readonly requiresMfa: boolean;
  readonly requiresReason: boolean;
};

export function getAdminActionPolicy(action: unknown): AdminActionPolicy | null {
  if (typeof action !== 'string' || !PermissionActions.includes(action as PermissionAction)) {
    return null;
  }
  return AdminActionMatrix[action as PermissionAction];
}

export function evaluateAdminAction(
  context: AdminAuthorizationContext,
  action: unknown,
): AdminAuthorizationDecision {
  const policy = getAdminActionPolicy(action);
  if (!policy) {
    return {
      allowed: false,
      reason: 'unknown_action',
      requiresMfa: false,
      requiresReason: false,
    };
  }

  if (typeof context.role !== 'string' || !AdminRoles.includes(context.role as AdminRole)) {
    return {
      allowed: false,
      reason: 'unknown_role',
      requiresMfa: policy.requiresMfa,
      requiresReason: false,
    };
  }

  const role = context.role as AdminRole;
  const requiresReason = policy.reasonRoles.includes(role);
  if (context.status !== undefined && context.status !== 'active') {
    return {
      allowed: false,
      reason: 'inactive_member',
      requiresMfa: policy.requiresMfa,
      requiresReason,
    };
  }

  if (!policy.roles.includes(role)) {
    return {
      allowed: false,
      reason: 'role_denied',
      requiresMfa: policy.requiresMfa,
      requiresReason,
    };
  }

  const mfaSatisfied = context.aal === 'aal2' && context.mfaState === 'verified';
  if (policy.requiresMfa && !mfaSatisfied) {
    return {
      allowed: false,
      reason: 'mfa_required',
      requiresMfa: true,
      requiresReason,
    };
  }

  return { allowed: true, reason: 'allowed', requiresMfa: policy.requiresMfa, requiresReason };
}
