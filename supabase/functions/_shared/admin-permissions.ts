import matrix from '../../../packages/contracts/src/admin-permissions.matrix.json' with { type: 'json' };

type AdminRole = 'owner' | 'admin' | 'support' | 'finance';
type AdminActionPolicy = {
  readonly roles: readonly AdminRole[];
  readonly requiresMfa: boolean;
  readonly reasonRoles: readonly AdminRole[];
};

const actions = matrix.actions as Record<string, AdminActionPolicy>;
const roles = new Set<AdminRole>(['owner', 'admin', 'support', 'finance']);

export type BackendAdminAuthorizationContext = {
  readonly role: unknown;
  readonly status?: unknown;
  readonly aal?: unknown;
  readonly mfaState?: unknown;
};

export type BackendAdminAuthorizationDecision = {
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

export function evaluateBackendAdminAction(
  context: BackendAdminAuthorizationContext,
  action: unknown,
): BackendAdminAuthorizationDecision {
  const policy = typeof action === 'string' ? actions[action] : undefined;
  if (!policy) {
    return {
      allowed: false,
      reason: 'unknown_action',
      requiresMfa: false,
      requiresReason: false,
    };
  }

  if (typeof context.role !== 'string' || !roles.has(context.role as AdminRole)) {
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
  if (policy.requiresMfa && (context.aal !== 'aal2' || context.mfaState !== 'verified')) {
    return {
      allowed: false,
      reason: 'mfa_required',
      requiresMfa: true,
      requiresReason,
    };
  }

  return { allowed: true, reason: 'allowed', requiresMfa: policy.requiresMfa, requiresReason };
}
