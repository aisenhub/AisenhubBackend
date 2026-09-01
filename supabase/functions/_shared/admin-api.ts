import { healthResponse } from './health.ts';
import {
  evaluateBackendAdminAction,
  type BackendAdminAuthorizationContext,
  type BackendAdminAuthorizationDecision,
} from './admin-permissions.ts';
import {
  apiPath,
  errorResponse,
  jsonResponse,
  preflightResponse,
  requestId,
  resolveOrigin,
  rpc,
  sessionCookie,
  sha256Hex,
  withCors,
} from './platform-api.ts';

type AdminSessionRow = {
  readonly user_id: string;
  readonly display_name: string | null;
  readonly role: 'owner' | 'admin' | 'support' | 'finance';
  readonly aal: 'aal1' | 'aal2';
  readonly mfa_state: 'not_required' | 'required' | 'verified';
  readonly expires_at: string;
};

export function authorizeAdminAction(
  context: BackendAdminAuthorizationContext,
  action: unknown,
): BackendAdminAuthorizationDecision {
  return evaluateBackendAdminAction(context, action);
}

function isAdminSessionRow(value: unknown): value is AdminSessionRow {
  if (!value || typeof value !== 'object') return false;
  const row = value as Record<string, unknown>;
  return (
    typeof row.user_id === 'string' &&
    (typeof row.display_name === 'string' || row.display_name === null) &&
    ['owner', 'admin', 'support', 'finance'].includes(String(row.role)) &&
    ['aal1', 'aal2'].includes(String(row.aal)) &&
    ['not_required', 'required', 'verified'].includes(String(row.mfa_state)) &&
    typeof row.expires_at === 'string'
  );
}

async function adminSessionRead(request: Request, id: string): Promise<Response> {
  const rawToken = sessionCookie(request);
  if (!rawToken) {
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  }

  try {
    const rows = await rpc<AdminSessionRow>('get_admin_session', {
      p_token_hash: await sha256Hex(rawToken),
    });
    const session = rows.length === 1 && isAdminSessionRow(rows[0]) ? rows[0] : null;
    if (!session) {
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    }

    return jsonResponse(
      {
        authenticated: true,
        identity: {
          userId: session.user_id,
          displayName: session.display_name,
        },
        role: session.role,
        aal: session.aal,
        mfaState: session.mfa_state,
        expiresAt: session.expires_at,
      },
      200,
      id,
    );
  } catch {
    return errorResponse('INTERNAL_ERROR', 'The Admin session could not be read.', 502, id);
  }
}

export async function routePlatformAdmin(
  request: Request,
  health: (functionName: string) => Response = healthResponse,
): Promise<Response> {
  const id = requestId();
  const resolved = await resolveOrigin(request, id);
  if (resolved instanceof Response) return resolved;
  if (request.method === 'OPTIONS') {
    return resolved
      ? preflightResponse(request, id, resolved)
      : errorResponse('ORIGIN_NOT_ALLOWED', 'A request Origin is required.', 403, id);
  }

  const path = apiPath(request);
  if (path === '/' || path === '') return health('platform-admin');
  if (path === '/v1/admin/session') {
    if (request.method !== 'GET') {
      return withCors(
        errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id),
        resolved,
      );
    }
    return withCors(await adminSessionRead(request, id), resolved);
  }

  return withCors(
    errorResponse('VALIDATION_ERROR', 'The requested route was not found.', 404, id),
    resolved,
  );
}
