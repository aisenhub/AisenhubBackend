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
  serviceRpc,
  ServiceRpcError,
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

async function activeAdminSession(request: Request): Promise<AdminSessionRow | null> {
  const rawToken = sessionCookie(request);
  if (!rawToken) return null;

  const rows = await rpc<AdminSessionRow>('get_admin_session', {
    p_token_hash: await sha256Hex(rawToken),
  });
  return rows.length === 1 && isAdminSessionRow(rows[0]) ? rows[0] : null;
}

type AdminQueryOptions = {
  readonly cursor: string | null;
  readonly limit: number;
  readonly search: string | null;
  readonly status: string | null;
  readonly sort: string;
  readonly direction: 'asc' | 'desc';
};

function parseAdminQuery(request: Request, id: string): AdminQueryOptions | Response {
  const params = new URL(request.url).searchParams;
  const rawLimit = params.get('limit');
  const limit = rawLimit === null ? 25 : Number(rawLimit);
  const direction = params.get('direction') ?? 'desc';
  const cursor = params.get('cursor');
  const search = params.get('search');
  const status = params.get('status');
  const sort = params.get('sort') ?? 'createdAt';

  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    return errorResponse('VALIDATION_ERROR', 'The page size is invalid.', 400, id);
  }
  if (direction !== 'asc' && direction !== 'desc') {
    return errorResponse('VALIDATION_ERROR', 'The sort direction is invalid.', 400, id);
  }
  if (cursor !== null && (cursor === '' || cursor.length > 512)) {
    return errorResponse('VALIDATION_ERROR', 'The cursor is invalid.', 400, id);
  }
  if (search !== null && (search === '' || search.length > 200)) {
    return errorResponse('VALIDATION_ERROR', 'The search value is invalid.', 400, id);
  }
  if (status !== null && (status === '' || status.length > 50)) {
    return errorResponse('VALIDATION_ERROR', 'The status filter is invalid.', 400, id);
  }
  if (!/^[A-Za-z][A-Za-z0-9]*$/.test(sort)) {
    return errorResponse('VALIDATION_ERROR', 'The sort field is invalid.', 400, id);
  }

  return { cursor, limit, search, status, sort, direction };
}

async function adminQueryRead(request: Request, resource: string, id: string): Promise<Response> {
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }

  const rawToken = sessionCookie(request);
  if (!rawToken) {
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  }

  const parsed = parseAdminQuery(request, id);
  if (parsed instanceof Response) return parsed;

  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const rows = await serviceRpc<unknown>('admin_query_resource', {
      p_actor_id: session.user_id,
      p_resource: resource,
      p_cursor: parsed.cursor,
      p_limit: parsed.limit,
      p_search: parsed.search,
      p_status: parsed.status,
      p_sort: parsed.sort,
      p_direction: parsed.direction,
    });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Admin query returned an invalid result.',
        502,
        id,
      );
    }
    return jsonResponse(rows[0], 200, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === '42501') {
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '22023') {
      return errorResponse('VALIDATION_ERROR', 'The Admin query is invalid.', 400, id);
    }
    return errorResponse('INTERNAL_ERROR', 'The Admin query could not be read.', 502, id);
  }
}

async function adminSystemHealthRead(request: Request, id: string): Promise<Response> {
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }
  if (!sessionCookie(request)) {
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  }
  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    return jsonResponse(
      {
        status: 'healthy',
        checks: [
          { name: 'database', status: 'healthy' },
          { name: 'authentication', status: 'healthy' },
          { name: 'platform-admin', status: 'healthy' },
        ],
      },
      200,
      id,
    );
  } catch {
    return errorResponse('INTERNAL_ERROR', 'System health could not be read.', 502, id);
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
  if (path === '/v1/admin/system-health') {
    return withCors(await adminSystemHealthRead(request, id), resolved);
  }
  const queryMatch = path.match(
    /^\/v1\/admin\/(applications|users|entitlements|redemptions|feedback|audit-logs)$/,
  );
  if (queryMatch) {
    return withCors(await adminQueryRead(request, queryMatch[1], id), resolved);
  }

  return withCors(
    errorResponse('VALIDATION_ERROR', 'The requested route was not found.', 404, id),
    resolved,
  );
}
