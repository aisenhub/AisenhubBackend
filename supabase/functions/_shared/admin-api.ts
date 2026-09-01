import { healthResponse } from './health.ts';
import {
  evaluateBackendAdminAction,
  type BackendAdminAuthorizationContext,
  type BackendAdminAuthorizationDecision,
} from './admin-permissions.ts';
import {
  apiPath,
  errorResponse,
  enforceWritePreconditions,
  jsonResponse,
  parseJsonObject,
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
import { generateRedemptionCodes, redemptionPepperFromEnv } from './redemption-code.ts';

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
    const catalogResources = new Set([
      'origins',
      'features',
      'product-versions',
      'prices',
      'redemption-batches',
      'redemption-codes',
    ]);
    const customerResources = new Set(['account-deletion-requests']);
    const rows = await serviceRpc<unknown>(
      catalogResources.has(resource)
        ? 'admin_query_catalog_resource'
        : customerResources.has(resource)
          ? 'admin_query_customer_resource'
          : 'admin_query_resource',
      {
        p_actor_id: session.user_id,
        p_resource: resource,
        p_cursor: parsed.cursor,
        p_limit: parsed.limit,
        p_search: parsed.search,
        p_status: parsed.status,
        p_sort: parsed.sort,
        p_direction: parsed.direction,
      },
    );
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

async function adminUserOverviewRead(
  request: Request,
  userId: string,
  id: string,
): Promise<Response> {
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) {
    return errorResponse('VALIDATION_ERROR', 'The User ID is invalid.', 400, id);
  }
  if (!sessionCookie(request)) {
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  }
  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const rows = await serviceRpc<unknown>('admin_user_overview', {
      p_actor_id: session.user_id,
      p_user_id: userId,
    });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The User overview returned an invalid result.',
        502,
        id,
      );
    }
    return jsonResponse(rows[0], 200, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === '42501') {
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0002') {
      return errorResponse('ADMIN_RESOURCE_NOT_FOUND', 'The User was not found.', 404, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '22023') {
      return errorResponse('VALIDATION_ERROR', 'The User overview request is invalid.', 400, id);
    }
    return errorResponse('INTERNAL_ERROR', 'The User overview could not be read.', 502, id);
  }
}

async function adminProductOverviewRead(
  request: Request,
  productId: string,
  id: string,
): Promise<Response> {
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId)
  ) {
    return errorResponse('VALIDATION_ERROR', 'The Product ID is invalid.', 400, id);
  }
  if (!sessionCookie(request)) {
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  }
  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const rows = await serviceRpc<unknown>('admin_product_overview', {
      p_actor_id: session.user_id,
      p_product_id: productId,
    });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Product overview returned an invalid result.',
        502,
        id,
      );
    }
    return jsonResponse(rows[0], 200, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === '42501') {
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    }
    return errorResponse('INTERNAL_ERROR', 'The Product overview could not be read.', 502, id);
  }
}

async function adminCatalogDetailRead(
  request: Request,
  resource: string,
  resourceId: string,
  id: string,
): Promise<Response> {
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(resourceId)
  ) {
    return errorResponse('VALIDATION_ERROR', 'The resource ID is invalid.', 400, id);
  }
  if (!sessionCookie(request)) {
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  }
  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const rows = await serviceRpc<unknown>('admin_catalog_resource_detail', {
      p_actor_id: session.user_id,
      p_resource: resource,
      p_id: resourceId,
    });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Admin resource detail returned an invalid result.',
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
      return errorResponse('VALIDATION_ERROR', 'The Admin resource is invalid.', 400, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0002') {
      return errorResponse(
        'ADMIN_RESOURCE_NOT_FOUND',
        'The Admin resource was not found.',
        404,
        id,
      );
    }
    return errorResponse('INTERNAL_ERROR', 'The Admin resource could not be read.', 502, id);
  }
}

type DraftMutationRoute = {
  readonly action: string;
  readonly resourceId: string | null;
  readonly parentId: string | null;
  readonly creates: boolean;
};

type CatalogCommandRoute = {
  readonly action: string;
  readonly permission: string;
  readonly resourceId: string;
};

type CustomerCommandRoute = {
  readonly action:
    | 'grant_entitlement'
    | 'revoke_entitlement'
    | 'restore_entitlement'
    | 'disable_user'
    | 'process_account_deletion';
  readonly permission: string;
  readonly resourceId: string;
};

function customerCommandRoute(request: Request, path: string): CustomerCommandRoute | null {
  if (request.method !== 'POST') return null;

  const grant = path.match(/^\/v1\/admin\/users\/([^/]+)\/entitlements\/grant$/);
  if (grant) {
    return { action: 'grant_entitlement', permission: 'entitlements.grant', resourceId: grant[1] };
  }

  const entitlement = path.match(/^\/v1\/admin\/entitlements\/([^/]+)\/(revoke|restore)$/);
  if (entitlement) {
    const action = entitlement[2] === 'revoke' ? 'revoke_entitlement' : 'restore_entitlement';
    return {
      action,
      permission: `entitlements.${entitlement[2]}`,
      resourceId: entitlement[1],
    };
  }

  const disable = path.match(/^\/v1\/admin\/users\/([^/]+)\/disable$/);
  if (disable) {
    return { action: 'disable_user', permission: 'users.disable', resourceId: disable[1] };
  }

  const processDeletion = path.match(/^\/v1\/admin\/account-deletion-requests\/([^/]+)\/process$/);
  if (processDeletion) {
    return {
      action: 'process_account_deletion',
      permission: 'account_deletion.process',
      resourceId: processDeletion[1],
    };
  }

  return null;
}

async function adminCustomerCommand(
  request: Request,
  route: CustomerCommandRoute,
  id: string,
): Promise<Response> {
  const body = await parseJsonObject(request);
  if (!body) return errorResponse('VALIDATION_ERROR', 'A JSON object body is required.', 400, id);
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      route.resourceId,
    )
  ) {
    return errorResponse('VALIDATION_ERROR', 'The Customer command target is invalid.', 400, id);
  }

  const reason = typeof body.reason === 'string' ? body.reason.trim() : '';
  const confirmation = body.confirmation;
  const payload = { ...body };
  delete payload.reason;
  delete payload.confirmation;
  const idempotencyKey = request.headers.get('idempotency-key')?.trim() ?? '';
  if (!idempotencyKey || idempotencyKey.length > 255 || !reason || reason.length > 1000) {
    return errorResponse('VALIDATION_ERROR', 'A reason and Idempotency-Key are required.', 400, id);
  }
  if (confirmation !== true) {
    return errorResponse('VALIDATION_ERROR', 'Explicit command confirmation is required.', 400, id);
  }

  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const decision = authorizeAdminAction(
      { role: session.role, status: 'active', aal: session.aal, mfaState: session.mfa_state },
      route.permission,
    );
    if (!decision.allowed) {
      return errorResponse(
        decision.reason === 'mfa_required' ? 'MFA_REQUIRED' : 'ADMIN_ACCESS_DENIED',
        decision.reason === 'mfa_required'
          ? 'MFA is required for this Customer command.'
          : 'Admin access is denied.',
        403,
        id,
      );
    }

    const requestHash = await sha256Hex(
      JSON.stringify({
        action: route.action,
        resourceId: route.resourceId,
        payload,
        reason,
        confirmation,
      }),
    );
    const rows = await serviceRpc<unknown>('admin_customer_command', {
      p_actor_id: session.user_id,
      p_action: route.action,
      p_resource_id: route.resourceId,
      p_payload: payload,
      p_reason: reason,
      p_idempotency_key: idempotencyKey,
      p_request_hash: requestHash,
      p_request_id: id,
    });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Customer command returned an invalid result.',
        502,
        id,
      );
    }
    return jsonResponse(rows[0], 200, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === '42501') {
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '40001') {
      return errorResponse(
        'RESOURCE_VERSION_CONFLICT',
        'The Customer command is already in progress or the resource changed.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0001') {
      return errorResponse(
        'IDEMPOTENCY_KEY_REUSED',
        'The request key was already used for another request.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0002') {
      return errorResponse(
        'ADMIN_RESOURCE_NOT_FOUND',
        'The Customer resource was not found.',
        404,
        id,
      );
    }
    if (error instanceof ServiceRpcError && ['23505', '23514'].includes(error.databaseCode ?? '')) {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'The Customer state transition is invalid.',
        409,
        id,
      );
    }
    if (
      error instanceof ServiceRpcError &&
      ['22023', '22P02', '23503'].includes(error.databaseCode ?? '')
    ) {
      return errorResponse('VALIDATION_ERROR', 'The Customer command is invalid.', 400, id);
    }
    return errorResponse('INTERNAL_ERROR', 'The Customer command could not be completed.', 502, id);
  }
}

type RedemptionCommandRoute = {
  readonly action:
    | 'create_redemption_batch'
    | 'generate_redemption_codes'
    | 'pause_redemption_batch'
    | 'close_redemption_batch';
  readonly permission: string;
  readonly resourceId: string | null;
  readonly creates: boolean;
};

function redemptionCommandRoute(request: Request, path: string): RedemptionCommandRoute | null {
  if (request.method !== 'POST') return null;
  if (path === '/v1/admin/redemption-batches') {
    return {
      action: 'create_redemption_batch',
      permission: 'redemption_batches.generate_codes',
      resourceId: null,
      creates: true,
    };
  }
  const command = path.match(/^\/v1\/admin\/redemption-batches\/([^/]+)\/(generate|pause|close)$/);
  if (!command) return null;
  return {
    action:
      `${command[2]}_redemption_${command[2] === 'generate' ? 'codes' : 'batch'}` as RedemptionCommandRoute['action'],
    permission: `redemption_batches.${command[2] === 'generate' ? 'generate_codes' : command[2]}`,
    resourceId: command[1],
    creates: false,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

async function adminRedemptionCommand(
  request: Request,
  route: RedemptionCommandRoute,
  id: string,
): Promise<Response> {
  const body = await parseJsonObject(request);
  if (!body) return errorResponse('VALIDATION_ERROR', 'A JSON object body is required.', 400, id);
  const reason = typeof body.reason === 'string' ? body.reason.trim() : '';
  const confirmation = body.confirmation;
  const payload = { ...body };
  delete payload.reason;
  delete payload.confirmation;
  const idempotencyKey = request.headers.get('idempotency-key')?.trim() ?? '';
  if (!idempotencyKey || idempotencyKey.length > 255 || !reason || reason.length > 1000) {
    return errorResponse('VALIDATION_ERROR', 'A reason and Idempotency-Key are required.', 400, id);
  }
  if (confirmation !== true) {
    return errorResponse('VALIDATION_ERROR', 'Explicit command confirmation is required.', 400, id);
  }

  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const decision = authorizeAdminAction(
      { role: session.role, status: 'active', aal: session.aal, mfaState: session.mfa_state },
      route.permission,
    );
    if (!decision.allowed) {
      return errorResponse(
        decision.reason === 'mfa_required' ? 'MFA_REQUIRED' : 'ADMIN_ACCESS_DENIED',
        decision.reason === 'mfa_required'
          ? 'MFA is required for this Redemption command.'
          : 'Admin access is denied.',
        403,
        id,
      );
    }

    let commandPayload = payload;
    if (route.action === 'generate_redemption_codes') {
      if (!route.resourceId)
        return errorResponse('VALIDATION_ERROR', 'A batch ID is required.', 400, id);
      const detailRows = await serviceRpc<unknown>('admin_catalog_resource_detail', {
        p_actor_id: session.user_id,
        p_resource: 'redemption-batches',
        p_id: route.resourceId,
      });
      const detail = detailRows[0];
      if (
        !isRecord(detail) ||
        typeof detail.codePrefix !== 'string' ||
        typeof detail.quantity !== 'number'
      ) {
        return errorResponse('INTERNAL_ERROR', 'The Redemption batch detail is invalid.', 502, id);
      }
      const requestedQuantity =
        typeof payload.quantity === 'number' ? payload.quantity : detail.quantity;
      const { pepper, pepperVersion } = redemptionPepperFromEnv((name) => Deno.env.get(name));
      const materials = await generateRedemptionCodes(
        detail.codePrefix,
        requestedQuantity,
        pepper,
        pepperVersion,
      );
      commandPayload = {
        quantity: requestedQuantity,
        codeRecords: materials.map(({ codeHash, codeHint, pepperVersion: version }) => ({
          codeHash,
          codeHint,
          pepperVersion: version,
        })),
      };
      const requestHash = await sha256Hex(
        JSON.stringify({
          action: route.action,
          resourceId: route.resourceId,
          payload,
          reason,
          confirmation,
        }),
      );
      const rows = await serviceRpc<unknown>('admin_redemption_command', {
        p_actor_id: session.user_id,
        p_action: route.action,
        p_resource_id: route.resourceId,
        p_payload: commandPayload,
        p_reason: reason,
        p_idempotency_key: idempotencyKey,
        p_request_hash: requestHash,
        p_request_id: id,
      });
      if (rows.length !== 1 || !isRecord(rows[0])) {
        return errorResponse(
          'INTERNAL_ERROR',
          'The Redemption command returned an invalid result.',
          502,
          id,
        );
      }
      const safe = rows[0];
      const safeCodes = Array.isArray(safe.codes) ? safe.codes : [];
      const freshByHint = new Map(
        materials.map((material) => [material.codeHint, material.plaintext]),
      );
      const response = {
        ...safe,
        codes: safeCodes.map((code) => {
          if (!isRecord(code)) return code;
          const plaintext =
            typeof code.codeHint === 'string' ? freshByHint.get(code.codeHint) : undefined;
          return plaintext ? { ...code, code: plaintext } : code;
        }),
      };
      return jsonResponse(response, 200, id);
    }

    const requestHash = await sha256Hex(
      JSON.stringify({
        action: route.action,
        resourceId: route.resourceId,
        payload,
        reason,
        confirmation,
      }),
    );
    const rows = await serviceRpc<unknown>('admin_redemption_command', {
      p_actor_id: session.user_id,
      p_action: route.action,
      p_resource_id: route.resourceId,
      p_payload: commandPayload,
      p_reason: reason,
      p_idempotency_key: idempotencyKey,
      p_request_hash: requestHash,
      p_request_id: id,
    });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Redemption command returned an invalid result.',
        502,
        id,
      );
    }
    return jsonResponse(rows[0], route.creates ? 201 : 200, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === '42501') {
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '40001') {
      return errorResponse(
        'RESOURCE_VERSION_CONFLICT',
        'The Redemption command is already in progress or the resource changed.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0001') {
      return errorResponse(
        'IDEMPOTENCY_KEY_REUSED',
        'The request key was already used for another request.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0002') {
      return errorResponse(
        'ADMIN_RESOURCE_NOT_FOUND',
        'The Admin resource was not found.',
        404,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '23514') {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'The Redemption state transition is invalid.',
        409,
        id,
      );
    }
    if (
      error instanceof ServiceRpcError &&
      ['22023', '22P02', '23503', '23505'].includes(error.databaseCode ?? '')
    ) {
      return errorResponse('VALIDATION_ERROR', 'The Redemption command is invalid.', 400, id);
    }
    if (
      error instanceof Error &&
      /REDEMPTION_PEPPER|redemption code count|valid uppercase/i.test(error.message)
    ) {
      return errorResponse(
        'INTERNAL_ERROR',
        'Redemption code generation is not configured correctly.',
        502,
        id,
      );
    }
    return errorResponse(
      'INTERNAL_ERROR',
      'The Redemption command could not be completed.',
      502,
      id,
    );
  }
}

function catalogCommandRoute(request: Request, path: string): CatalogCommandRoute | null {
  if (request.method !== 'POST') return null;

  const publish = path.match(/^\/v1\/admin\/product-versions\/([^/]+)\/(publish|retire)$/);
  if (publish) {
    return {
      action: `${publish[2]}_product_version`,
      permission: `product_versions.${publish[2]}`,
      resourceId: publish[1],
    };
  }

  const setCurrent = path.match(/^\/v1\/admin\/products\/([^/]+)\/set-current-version$/);
  if (setCurrent) {
    return {
      action: 'set_current_product_version',
      permission: 'product_versions.set_current',
      resourceId: setCurrent[1],
    };
  }

  const productionOrigin = path.match(
    /^\/v1\/admin\/app-origins\/([^/]+)\/change-production-origin$/,
  );
  if (productionOrigin) {
    return {
      action: 'change_production_origin',
      permission: 'applications.change_production_origin',
      resourceId: productionOrigin[1],
    };
  }

  return null;
}

async function adminCatalogCommand(
  request: Request,
  route: CatalogCommandRoute,
  id: string,
): Promise<Response> {
  const body = await parseJsonObject(request);
  if (!body) return errorResponse('VALIDATION_ERROR', 'A JSON object body is required.', 400, id);
  const reason = typeof body.reason === 'string' ? body.reason.trim() : '';
  const confirmation = body.confirmation;
  const payload = { ...body };
  delete payload.reason;
  delete payload.confirmation;
  const idempotencyKey = request.headers.get('idempotency-key')?.trim() ?? '';
  if (!idempotencyKey || idempotencyKey.length > 255 || !reason || reason.length > 1000) {
    return errorResponse('VALIDATION_ERROR', 'A reason and Idempotency-Key are required.', 400, id);
  }
  if (confirmation !== true) {
    return errorResponse('VALIDATION_ERROR', 'Explicit command confirmation is required.', 400, id);
  }

  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const decision = authorizeAdminAction(
      { role: session.role, status: 'active', aal: session.aal, mfaState: session.mfa_state },
      route.permission,
    );
    if (!decision.allowed) {
      return errorResponse(
        decision.reason === 'mfa_required' ? 'MFA_REQUIRED' : 'ADMIN_ACCESS_DENIED',
        decision.reason === 'mfa_required'
          ? 'MFA is required for this Catalog command.'
          : 'Admin access is denied.',
        403,
        id,
      );
    }
    const requestHash = await sha256Hex(
      JSON.stringify({
        action: route.action,
        resourceId: route.resourceId,
        payload,
        reason,
        confirmation,
      }),
    );
    const rows = await serviceRpc<unknown>('admin_catalog_command', {
      p_actor_id: session.user_id,
      p_action: route.action,
      p_resource_id: route.resourceId,
      p_payload: payload,
      p_reason: reason,
      p_idempotency_key: idempotencyKey,
      p_request_hash: requestHash,
      p_request_id: id,
    });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Catalog command returned an invalid result.',
        502,
        id,
      );
    }
    return jsonResponse(rows[0], 200, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === '42501') {
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '40001') {
      return errorResponse(
        'RESOURCE_VERSION_CONFLICT',
        'The Catalog command is already in progress or the resource changed.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0001') {
      return errorResponse(
        'IDEMPOTENCY_KEY_REUSED',
        'The request key was already used for another request.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0002') {
      return errorResponse(
        'ADMIN_RESOURCE_NOT_FOUND',
        'The Admin resource was not found.',
        404,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '23514') {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'The Catalog state transition is invalid.',
        409,
        id,
      );
    }
    if (
      error instanceof ServiceRpcError &&
      ['22023', '22P02', '23503', '23505'].includes(error.databaseCode ?? '')
    ) {
      return errorResponse('VALIDATION_ERROR', 'The Catalog command is invalid.', 400, id);
    }
    return errorResponse('INTERNAL_ERROR', 'The Catalog command could not be completed.', 502, id);
  }
}

function draftMutationRoute(request: Request, path: string): DraftMutationRoute | null {
  if (request.method === 'POST') {
    if (path === '/v1/admin/applications')
      return { action: 'create_application', resourceId: null, parentId: null, creates: true };
    if (path === '/v1/admin/features')
      return { action: 'create_feature', resourceId: null, parentId: null, creates: true };
    if (path === '/v1/admin/products')
      return { action: 'create_product', resourceId: null, parentId: null, creates: true };
    const origin = path.match(/^\/v1\/admin\/applications\/([^/]+)\/origins$/);
    if (origin)
      return { action: 'create_origin', resourceId: null, parentId: origin[1], creates: true };
    const version = path.match(/^\/v1\/admin\/products\/([^/]+)\/versions$/);
    if (version)
      return {
        action: 'create_product_version',
        resourceId: null,
        parentId: version[1],
        creates: true,
      };
    const price = path.match(/^\/v1\/admin\/product-versions\/([^/]+)\/prices$/);
    if (price)
      return { action: 'create_price', resourceId: null, parentId: price[1], creates: true };
  }
  if (request.method === 'PATCH') {
    const update = path.match(
      /^\/v1\/admin\/(applications|origins|features|products|product-versions|prices)\/([^/]+)$/,
    );
    if (update) {
      const actionByResource: Record<string, string> = {
        applications: 'update_application',
        origins: 'update_origin',
        features: 'update_feature',
        products: 'update_product',
        'product-versions': 'update_product_version',
        prices: 'update_price',
      };
      return {
        action: actionByResource[update[1]],
        resourceId: update[2],
        parentId: null,
        creates: false,
      };
    }
  }
  return null;
}

async function adminCatalogDraftMutation(
  request: Request,
  route: DraftMutationRoute,
  id: string,
): Promise<Response> {
  const body = await parseJsonObject(request);
  if (!body) return errorResponse('VALIDATION_ERROR', 'A JSON object body is required.', 400, id);
  const reason = typeof body.reason === 'string' ? body.reason.trim() : '';
  const expectedUpdatedAt =
    typeof body.expectedUpdatedAt === 'string' ? body.expectedUpdatedAt : null;
  const payload = { ...body };
  delete payload.reason;
  delete payload.expectedUpdatedAt;
  const idempotencyKey = request.headers.get('idempotency-key')?.trim() ?? '';
  if (!idempotencyKey || idempotencyKey.length > 255 || !reason || reason.length > 1000) {
    return errorResponse('VALIDATION_ERROR', 'A reason and Idempotency-Key are required.', 400, id);
  }
  if (!route.creates && !expectedUpdatedAt) {
    return errorResponse(
      'VALIDATION_ERROR',
      'expectedUpdatedAt is required for draft updates.',
      400,
      id,
    );
  }
  if (route.creates && expectedUpdatedAt !== null) {
    return errorResponse(
      'VALIDATION_ERROR',
      'expectedUpdatedAt is not accepted for draft creation.',
      400,
      id,
    );
  }
  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const decision = authorizeAdminAction(
      { role: session.role, status: 'active', aal: session.aal, mfaState: session.mfa_state },
      'products.create',
    );
    if (!decision.allowed) {
      return errorResponse(
        decision.reason === 'mfa_required' ? 'MFA_REQUIRED' : 'ADMIN_ACCESS_DENIED',
        decision.reason === 'mfa_required'
          ? 'MFA is required for catalog draft changes.'
          : 'Admin access is denied.',
        403,
        id,
      );
    }
    const requestHash = await sha256Hex(
      JSON.stringify({
        action: route.action,
        resourceId: route.resourceId,
        parentId: route.parentId,
        payload,
        expectedUpdatedAt,
        reason,
      }),
    );
    const rows = await serviceRpc<unknown>('admin_catalog_draft_command', {
      p_actor_id: session.user_id,
      p_action: route.action,
      p_resource_id: route.resourceId,
      p_parent_id: route.parentId,
      p_payload: payload,
      p_expected_updated_at: expectedUpdatedAt,
      p_reason: reason,
      p_idempotency_key: idempotencyKey,
      p_request_hash: requestHash,
      p_request_id: id,
    });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The draft command returned an invalid result.',
        502,
        id,
      );
    }
    return jsonResponse(rows[0], route.creates ? 201 : 200, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === '42501') {
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '40001') {
      return errorResponse(
        'RESOURCE_VERSION_CONFLICT',
        'The resource changed before this draft update.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0001') {
      return errorResponse(
        'IDEMPOTENCY_KEY_REUSED',
        'The request key was already used for another request.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0002') {
      return errorResponse(
        'ADMIN_RESOURCE_NOT_FOUND',
        'The Admin resource was not found.',
        404,
        id,
      );
    }
    if (
      error instanceof ServiceRpcError &&
      ['22023', '22P02', '23503', '23505', '23514'].includes(error.databaseCode ?? '')
    ) {
      return errorResponse('VALIDATION_ERROR', 'The draft command is invalid.', 400, id);
    }
    return errorResponse('INTERNAL_ERROR', 'The draft command could not be completed.', 502, id);
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
  const productOverviewMatch = path.match(/^\/v1\/admin\/products\/([^/]+)\/overview$/);
  if (productOverviewMatch) {
    return withCors(await adminProductOverviewRead(request, productOverviewMatch[1], id), resolved);
  }
  const userOverviewMatch = path.match(/^\/v1\/admin\/users\/([^/]+)\/overview$/);
  if (userOverviewMatch) {
    return withCors(await adminUserOverviewRead(request, userOverviewMatch[1], id), resolved);
  }
  const redemptionRoute = redemptionCommandRoute(request, path);
  if (redemptionRoute) {
    const preconditionFailure = await enforceWritePreconditions(request, path, resolved, id);
    if (preconditionFailure) return withCors(preconditionFailure, resolved);
    return withCors(await adminRedemptionCommand(request, redemptionRoute, id), resolved);
  }
  const customerRoute = customerCommandRoute(request, path);
  if (customerRoute) {
    const preconditionFailure = await enforceWritePreconditions(request, path, resolved, id);
    if (preconditionFailure) return withCors(preconditionFailure, resolved);
    return withCors(await adminCustomerCommand(request, customerRoute, id), resolved);
  }
  const commandRoute = catalogCommandRoute(request, path);
  if (commandRoute) {
    const preconditionFailure = await enforceWritePreconditions(request, path, resolved, id);
    if (preconditionFailure) return withCors(preconditionFailure, resolved);
    return withCors(await adminCatalogCommand(request, commandRoute, id), resolved);
  }
  const draftRoute = draftMutationRoute(request, path);
  if (draftRoute) {
    const preconditionFailure = await enforceWritePreconditions(request, path, resolved, id);
    if (preconditionFailure) return withCors(preconditionFailure, resolved);
    return withCors(await adminCatalogDraftMutation(request, draftRoute, id), resolved);
  }
  const detailMatch = path.match(
    /^\/v1\/admin\/(applications|origins|features|products|product-versions|prices|redemption-batches|redemption-codes|redemptions|entitlements)\/([^/]+)$/,
  );
  if (detailMatch) {
    return withCors(
      await adminCatalogDetailRead(request, detailMatch[1], detailMatch[2], id),
      resolved,
    );
  }
  const queryMatch = path.match(
    /^\/v1\/admin\/(applications|users|origins|features|products|product-versions|prices|redemption-batches|redemption-codes|entitlements|redemptions|feedback|account-deletion-requests|audit-logs)$/,
  );
  if (queryMatch) {
    return withCors(await adminQueryRead(request, queryMatch[1], id), resolved);
  }

  return withCors(
    errorResponse('VALIDATION_ERROR', 'The requested route was not found.', 404, id),
    resolved,
  );
}
