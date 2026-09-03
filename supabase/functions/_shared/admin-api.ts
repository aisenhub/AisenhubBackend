import { healthResponse } from './health.ts';
import {
  evaluateBackendAdminAction,
  type BackendAdminAuthorizationContext,
  type BackendAdminAuthorizationDecision,
} from './admin-permissions.ts';
import {
  apiPath,
  bearerToken,
  errorResponse,
  jsonResponse,
  parseJsonObject,
  requestIdFromRequest,
} from './http.ts';
import { serviceRpc, ServiceRpcError, sha256Hex } from './db-gateway.ts';
import { preflightResponse, resolveOrigin, withCors } from './platform-api.ts';
import {
  createPlatformApplicationContextKernel,
  type ApplicationContextKernel,
} from './auth/platform-context.ts';
import { generateRedemptionCodes, redemptionPepperFromEnv } from './redemption-code.ts';

type AdminSessionRow = {
  readonly user_id: string;
  readonly display_name: string | null;
  readonly role: 'owner' | 'admin' | 'support' | 'finance';
  readonly aal: 'aal1' | 'aal2';
  readonly mfa_state: 'not_required' | 'required' | 'verified';
  readonly expires_at: string | null;
};

type AdminMembershipRow = {
  readonly user_id: string;
  readonly display_name: string | null;
  readonly role: 'owner' | 'admin' | 'support' | 'finance';
  readonly status: 'active';
};

let adminContextKernel: ApplicationContextKernel | null = null;

function getAdminContextKernel(): ApplicationContextKernel {
  return (adminContextKernel ??= createPlatformApplicationContextKernel());
}

export function authorizeAdminAction(
  context: BackendAdminAuthorizationContext,
  action: unknown,
): BackendAdminAuthorizationDecision {
  return evaluateBackendAdminAction(context, action);
}

async function adminSessionRead(request: Request, id: string): Promise<Response> {
  if (!bearerToken(request)) {
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  }

  try {
    const session = await activeAdminSession(request);
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
  if (!bearerToken(request)) return null;
  try {
    const context = await getAdminContextKernel().authenticate(request, 'admin-api');
    if (context.applicationSlug !== 'admin') return null;
    const rows = await serviceRpc<AdminMembershipRow>('resolve_admin_membership', {
      p_user_id: context.userId,
    });
    const membership = rows.length === 1 ? rows[0] : null;
    if (
      !membership ||
      membership.user_id !== context.userId ||
      membership.status !== 'active' ||
      !['owner', 'admin', 'support', 'finance'].includes(membership.role)
    ) {
      return null;
    }
    return {
      user_id: membership.user_id,
      display_name: membership.display_name,
      role: membership.role,
      aal: context.aal === 'aal2' ? 'aal2' : 'aal1',
      mfa_state: context.aal === 'aal2' ? 'verified' : 'required',
      expires_at: new Date(context.expiresAt * 1000).toISOString(),
    };
  } catch {
    return null;
  }
}

type AdminQueryOptions = {
  readonly applicationId: string | null;
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
  const applicationId = params.get('applicationId');
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
  if (
    applicationId !== null &&
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      applicationId,
    )
  ) {
    return errorResponse('VALIDATION_ERROR', 'The Application ID is invalid.', 400, id);
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

  return { applicationId, cursor, limit, search, status, sort, direction };
}

async function adminQueryRead(request: Request, resource: string, id: string): Promise<Response> {
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }

  const rawToken = bearerToken(request);
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
    const queryFunction =
      resource === 'orders' || resource === 'payments'
        ? 'admin_query_commerce_resource'
        : resource === 'products'
          ? 'admin_query_products'
          : catalogResources.has(resource)
            ? 'admin_query_catalog_resource'
            : customerResources.has(resource)
              ? 'admin_query_customer_resource'
              : 'admin_query_resource';
    const queryParams = {
      p_actor_id: session.user_id,
      p_resource: resource,
      p_cursor: parsed.cursor,
      p_limit: parsed.limit,
      p_search: parsed.search,
      p_status: parsed.status,
      p_sort: parsed.sort,
      p_direction: parsed.direction,
      ...(queryFunction === 'admin_query_resource'
        ? { p_application_id: parsed.applicationId }
        : {}),
    };
    const rows = await serviceRpc<unknown>(queryFunction, queryParams);
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
  if (!bearerToken(request)) {
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
  if (!bearerToken(request)) {
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

async function adminOrderOverviewRead(
  request: Request,
  orderId: string,
  id: string,
): Promise<Response> {
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(orderId)) {
    return errorResponse('VALIDATION_ERROR', 'The Order ID is invalid.', 400, id);
  }
  if (!bearerToken(request)) {
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  }
  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const rows = await serviceRpc<unknown>('admin_order_overview', {
      p_actor_id: session.user_id,
      p_order_id: orderId,
    });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Order overview returned an invalid result.',
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
      return errorResponse('ADMIN_RESOURCE_NOT_FOUND', 'The Order was not found.', 404, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '22023') {
      return errorResponse('VALIDATION_ERROR', 'The Order overview request is invalid.', 400, id);
    }
    return errorResponse('INTERNAL_ERROR', 'The Order overview could not be read.', 502, id);
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
  if (!bearerToken(request)) {
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

type OrderCommandRoute = {
  readonly action: 'verify_order';
  readonly permission: 'orders.verify';
  readonly resourceId: string;
};

type OrderItemCommandRoute = {
  readonly action: 'refund_order_item';
  readonly permission: 'order_items.refund';
  readonly resourceId: string;
};

function orderCommandRoute(request: Request, path: string): OrderCommandRoute | null {
  if (request.method !== 'POST') return null;
  const match = path.match(/^\/v1\/admin\/orders\/([^/]+)\/verify$/);
  return match
    ? { action: 'verify_order', permission: 'orders.verify', resourceId: match[1] }
    : null;
}

function orderItemCommandRoute(request: Request, path: string): OrderItemCommandRoute | null {
  if (request.method !== 'POST') return null;
  const match = path.match(/^\/v1\/admin\/order-items\/([^/]+)\/refund$/);
  return match
    ? { action: 'refund_order_item', permission: 'order_items.refund', resourceId: match[1] }
    : null;
}

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

async function adminOrderCommand(
  request: Request,
  route: OrderCommandRoute,
  id: string,
): Promise<Response> {
  const body = await parseJsonObject(request);
  if (!body) return errorResponse('VALIDATION_ERROR', 'A JSON object body is required.', 400, id);
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      route.resourceId,
    )
  ) {
    return errorResponse('VALIDATION_ERROR', 'The Order command target is invalid.', 400, id);
  }

  const allowedKeys = new Set([
    'paymentReference',
    'amountMinor',
    'currency',
    'reason',
    'confirmation',
  ]);
  if (Object.keys(body).some((key) => !allowedKeys.has(key))) {
    return errorResponse('VALIDATION_ERROR', 'The manual payment evidence is invalid.', 400, id);
  }
  const paymentReference =
    typeof body.paymentReference === 'string' ? body.paymentReference.trim() : '';
  const amountMinor = body.amountMinor;
  const currency = typeof body.currency === 'string' ? body.currency : '';
  const reason = typeof body.reason === 'string' ? body.reason.trim() : '';
  const confirmation = body.confirmation;
  const idempotencyKey = request.headers.get('idempotency-key')?.trim() ?? '';
  if (
    !paymentReference ||
    paymentReference.length > 200 ||
    /\s/.test(paymentReference) ||
    typeof amountMinor !== 'number' ||
    !Number.isSafeInteger(amountMinor) ||
    amountMinor < 0 ||
    !/^[A-Z]{3}$/.test(currency) ||
    !idempotencyKey ||
    idempotencyKey.length > 255 ||
    !reason ||
    reason.length > 1000
  ) {
    return errorResponse('VALIDATION_ERROR', 'The manual payment evidence is invalid.', 400, id);
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
          ? 'MFA is required for this Order command.'
          : 'Admin access is denied.',
        403,
        id,
      );
    }

    const requestHash = await sha256Hex(
      JSON.stringify({
        action: route.action,
        resourceId: route.resourceId,
        paymentReference,
        amountMinor,
        currency,
        reason,
        confirmation,
      }),
    );
    const rows = await serviceRpc<unknown>('admin_verify_order', {
      p_actor_id: session.user_id,
      p_order_id: route.resourceId,
      p_payment_reference: paymentReference,
      p_amount: amountMinor,
      p_currency: currency,
      p_reason: reason,
      p_idempotency_key: idempotencyKey,
      p_request_hash: requestHash,
      p_request_id: id,
    });
    if (rows.length !== 1 || !isRecord(rows[0])) {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Order command returned an invalid result.',
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
        'The Order command is already in progress or the resource changed.',
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
      return errorResponse('ORDER_NOT_FOUND', 'The Order was not found.', 404, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0003') {
      return errorResponse(
        'PAYMENT_AMOUNT_MISMATCH',
        'The payment evidence does not match the Order amount or currency.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0004') {
      return errorResponse(
        'ORDER_NOT_FULFILLABLE',
        'The Order is not eligible for verification.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0005') {
      return errorResponse(
        'VALIDATION_ERROR',
        'The payment reference does not match the Order.',
        400,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0006') {
      return errorResponse(
        'PAYMENT_NOT_FOUND',
        'A pending payment was not found for the Order.',
        404,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0007') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Order fulfillment audit could not be confirmed.',
        502,
        id,
      );
    }
    if (
      error instanceof ServiceRpcError &&
      ['22023', '22P02', '23503'].includes(error.databaseCode ?? '')
    ) {
      return errorResponse('VALIDATION_ERROR', 'The manual payment evidence is invalid.', 400, id);
    }
    if (error instanceof ServiceRpcError && ['23505', '23514'].includes(error.databaseCode ?? '')) {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'The Order state transition is invalid.',
        409,
        id,
      );
    }
    return errorResponse('INTERNAL_ERROR', 'The Order command could not be completed.', 502, id);
  }
}

async function adminOrderItemCommand(
  request: Request,
  route: OrderItemCommandRoute,
  id: string,
): Promise<Response> {
  const body = await parseJsonObject(request);
  if (!body) return errorResponse('VALIDATION_ERROR', 'A JSON object body is required.', 400, id);
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      route.resourceId,
    )
  ) {
    return errorResponse('VALIDATION_ERROR', 'The OrderItem command target is invalid.', 400, id);
  }

  const allowedKeys = new Set(['amountMinor', 'mode', 'reason', 'confirmation']);
  if (Object.keys(body).some((key) => !allowedKeys.has(key))) {
    return errorResponse('VALIDATION_ERROR', 'The refund request is invalid.', 400, id);
  }
  const amountMinor = body.amountMinor;
  const mode = body.mode;
  const reason = typeof body.reason === 'string' ? body.reason.trim() : '';
  const confirmation = body.confirmation;
  const idempotencyKey = request.headers.get('idempotency-key')?.trim() ?? '';
  if (
    typeof amountMinor !== 'number' ||
    !Number.isSafeInteger(amountMinor) ||
    amountMinor <= 0 ||
    !['compensation', 'return'].includes(String(mode)) ||
    !idempotencyKey ||
    idempotencyKey.length > 255 ||
    !reason ||
    reason.length > 1000
  ) {
    return errorResponse('VALIDATION_ERROR', 'The refund request is invalid.', 400, id);
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
          ? 'MFA is required for this OrderItem command.'
          : 'Admin access is denied.',
        403,
        id,
      );
    }

    const requestHash = await sha256Hex(
      JSON.stringify({
        action: route.action,
        resourceId: route.resourceId,
        amountMinor,
        mode,
        reason,
        confirmation,
      }),
    );
    const rows = await serviceRpc<unknown>('admin_refund_order_item', {
      p_actor_id: session.user_id,
      p_order_item_id: route.resourceId,
      p_amount: amountMinor,
      p_mode: mode,
      p_reason: reason,
      p_idempotency_key: idempotencyKey,
      p_request_hash: requestHash,
      p_request_id: id,
    });
    if (rows.length !== 1 || !isRecord(rows[0])) {
      return errorResponse(
        'INTERNAL_ERROR',
        'The OrderItem command returned an invalid result.',
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
        'The OrderItem command is already in progress or the resource changed.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0011') {
      return errorResponse(
        'IDEMPOTENCY_KEY_REUSED',
        'The request key was already used for another request.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0001') {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'The OrderItem refund state transition is invalid.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0002') {
      return errorResponse('ORDER_ITEM_NOT_FOUND', 'The OrderItem was not found.', 404, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0008') {
      return errorResponse(
        'REFUND_EXCEEDS_ITEM_TOTAL',
        'The refund exceeds the OrderItem total.',
        409,
        id,
      );
    }
    if (
      error instanceof ServiceRpcError &&
      ['22023', '22P02', '23503'].includes(error.databaseCode ?? '')
    ) {
      return errorResponse('VALIDATION_ERROR', 'The refund request is invalid.', 400, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '23505') {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'The OrderItem refund state transition is invalid.',
        409,
        id,
      );
    }
    return errorResponse(
      'INTERNAL_ERROR',
      'The OrderItem command could not be completed.',
      502,
      id,
    );
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
  if (!bearerToken(request)) {
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

async function adminOverviewRead(request: Request, id: string): Promise<Response> {
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }
  if (!bearerToken(request)) {
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  }
  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const rows = await serviceRpc<unknown>('admin_operations_overview', {
      p_actor_id: session.user_id,
    });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Admin overview returned an invalid result.',
        502,
        id,
      );
    }
    return jsonResponse(rows[0], 200, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === '42501') {
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    }
    return errorResponse('INTERNAL_ERROR', 'The Admin overview could not be read.', 502, id);
  }
}

type AdminApplicationMembershipApiRow = {
  readonly id: string;
  readonly application_id: string;
  readonly application_slug: string;
  readonly application_name: string;
  readonly user_id: string;
  readonly membership_status: string;
  readonly created_source: string;
  readonly joined_at: string;
  readonly activated_at: string | null;
  readonly suspended_at: string | null;
  readonly suspended_reason: string | null;
  readonly left_at: string | null;
  readonly deleted_at: string | null;
};

type AdminOAuthClientApiRow = {
  readonly id: string;
  readonly application_id: string;
  readonly provider: string;
  readonly external_client_id: string;
  readonly client_type: string;
  readonly environment: string;
  readonly name: string;
  readonly status: string;
  readonly created_at: string;
  readonly updated_at: string;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isUuid(value: unknown): value is string {
  return typeof value === 'string' && uuidPattern.test(value);
}

function hasOnlyKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const allowed = new Set(keys);
  return Object.keys(value).every((key) => allowed.has(key));
}

function mapAdminApplicationMembership(row: AdminApplicationMembershipApiRow) {
  return {
    id: row.id,
    applicationId: row.application_id,
    applicationSlug: row.application_slug,
    applicationName: row.application_name,
    userId: row.user_id,
    status: row.membership_status,
    createdSource: row.created_source,
    joinedAt: row.joined_at,
    activatedAt: row.activated_at,
    suspendedAt: row.suspended_at,
    suspendedReason: row.suspended_reason,
    leftAt: row.left_at,
    deletedAt: row.deleted_at,
  };
}

function mapAdminOAuthClient(row: AdminOAuthClientApiRow) {
  return {
    id: row.id,
    applicationId: row.application_id,
    provider: row.provider,
    externalClientId: row.external_client_id,
    clientType: row.client_type,
    environment: row.environment,
    name: row.name,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function adminApplicationActionResponse(error: unknown, id: string, subject: string): Response {
  if (error instanceof ServiceRpcError && error.databaseCode === '42501') {
    return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
  }
  if (error instanceof ServiceRpcError && error.databaseCode === '40001') {
    return errorResponse(
      'RESOURCE_VERSION_CONFLICT',
      `The ${subject} command is already in progress.`,
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
    return errorResponse('ADMIN_RESOURCE_NOT_FOUND', `The ${subject} was not found.`, 404, id);
  }
  if (error instanceof ServiceRpcError && error.databaseCode === '23514') {
    return errorResponse(
      'INVALID_STATE_TRANSITION',
      `The ${subject} state transition is invalid.`,
      409,
      id,
    );
  }
  if (
    error instanceof ServiceRpcError &&
    ['22023', '22P02', '23503', '23505'].includes(error.databaseCode ?? '')
  ) {
    return errorResponse('VALIDATION_ERROR', `The ${subject} command is invalid.`, 400, id);
  }
  return errorResponse('INTERNAL_ERROR', `The ${subject} command could not be completed.`, 502, id);
}

async function adminApplicationMembershipsRead(
  request: Request,
  applicationId: string,
  id: string,
): Promise<Response> {
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }
  if (!isUuid(applicationId))
    return errorResponse('VALIDATION_ERROR', 'The Application id is invalid.', 400, id);
  if (!bearerToken(request))
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const decision = authorizeAdminAction(
      { role: session.role, status: 'active', aal: session.aal, mfaState: session.mfa_state },
      'application_memberships.read',
    );
    if (!decision.allowed)
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const rows = await serviceRpc<AdminApplicationMembershipApiRow>(
      'admin_list_application_memberships',
      {
        p_actor_id: session.user_id,
        p_application_id: applicationId,
      },
    );
    return jsonResponse({ items: rows.map(mapAdminApplicationMembership) }, 200, id);
  } catch (error) {
    return adminApplicationActionResponse(error, id, 'Application membership');
  }
}

async function adminOAuthClientsRead(
  request: Request,
  applicationId: string,
  id: string,
): Promise<Response> {
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }
  if (!isUuid(applicationId))
    return errorResponse('VALIDATION_ERROR', 'The Application id is invalid.', 400, id);
  if (!bearerToken(request))
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const decision = authorizeAdminAction(
      { role: session.role, status: 'active', aal: session.aal, mfaState: session.mfa_state },
      'oauth_clients.read',
    );
    if (!decision.allowed)
      return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const rows = await serviceRpc<AdminOAuthClientApiRow>('admin_list_application_oauth_clients', {
      p_actor_id: session.user_id,
      p_application_id: applicationId,
    });
    return jsonResponse({ items: rows.map(mapAdminOAuthClient) }, 200, id);
  } catch (error) {
    return adminApplicationActionResponse(error, id, 'OAuth client list');
  }
}

async function adminApplicationOperationCommand(
  request: Request,
  kind: 'membership' | 'oauth',
  action: 'create' | 'suspend' | 'restore' | 'delete' | 'disable',
  applicationId: string,
  targetId: string | null,
  id: string,
): Promise<Response> {
  if (request.method !== 'POST')
    return errorResponse('VALIDATION_ERROR', 'Only POST requests are supported.', 405, id);
  if (!isUuid(applicationId) || (targetId !== null && !isUuid(targetId))) {
    return errorResponse(
      'VALIDATION_ERROR',
      'The Application operation target is invalid.',
      400,
      id,
    );
  }
  const body = await parseJsonObject(request);
  if (!body) return errorResponse('VALIDATION_ERROR', 'A JSON object body is required.', 400, id);
  const expectedKeys =
    kind === 'membership' && action === 'create'
      ? ['userId', 'createdSource', 'reason', 'confirmation']
      : kind === 'oauth' && action === 'create'
        ? [
            'provider',
            'externalClientId',
            'clientType',
            'environment',
            'name',
            'reason',
            'confirmation',
          ]
        : ['reason', 'confirmation'];
  if (
    !hasOnlyKeys(body, expectedKeys) ||
    body.confirmation !== true ||
    typeof body.reason !== 'string'
  ) {
    return errorResponse('VALIDATION_ERROR', 'The command body is invalid.', 400, id);
  }
  const reason = body.reason.trim();
  const idempotencyKey = request.headers.get('idempotency-key')?.trim() ?? '';
  if (!reason || reason.length > 1000 || !idempotencyKey || idempotencyKey.length > 255) {
    return errorResponse('VALIDATION_ERROR', 'A reason and Idempotency-Key are required.', 400, id);
  }
  if (kind === 'membership' && action === 'create' && !isUuid(body.userId)) {
    return errorResponse('VALIDATION_ERROR', 'The member User id is invalid.', 400, id);
  }
  if (
    kind === 'oauth' &&
    action === 'create' &&
    (typeof body.provider !== 'string' ||
      !body.provider.trim() ||
      body.provider.length > 100 ||
      typeof body.externalClientId !== 'string' ||
      !body.externalClientId.trim() ||
      body.externalClientId.length > 255 ||
      !['public', 'confidential'].includes(String(body.clientType)) ||
      !['development', 'staging', 'production'].includes(String(body.environment)) ||
      typeof body.name !== 'string' ||
      !body.name.trim() ||
      body.name.length > 200)
  ) {
    return errorResponse('VALIDATION_ERROR', 'The OAuth client fields are invalid.', 400, id);
  }
  try {
    const session = await activeAdminSession(request);
    if (!session) return errorResponse('ADMIN_ACCESS_DENIED', 'Admin access is denied.', 403, id);
    const permission =
      kind === 'membership' ? 'application_memberships.manage' : 'oauth_clients.manage';
    const decision = authorizeAdminAction(
      { role: session.role, status: 'active', aal: session.aal, mfaState: session.mfa_state },
      permission,
    );
    if (!decision.allowed) {
      return errorResponse(
        decision.reason === 'mfa_required' ? 'MFA_REQUIRED' : 'ADMIN_ACCESS_DENIED',
        decision.reason === 'mfa_required'
          ? 'MFA is required for this Admin command.'
          : 'Admin access is denied.',
        403,
        id,
      );
    }
    const payload = { ...body, reason };
    const requestHash = await sha256Hex(
      JSON.stringify({ kind, action, applicationId, targetId, payload }),
    );
    const rows =
      kind === 'membership'
        ? await serviceRpc<unknown>('admin_application_membership_command', {
            p_actor_id: session.user_id,
            p_action: action,
            p_application_id: applicationId,
            p_user_id: action === 'create' ? body.userId : null,
            p_membership_id: targetId,
            p_reason: reason,
            p_idempotency_key: idempotencyKey,
            p_request_hash: requestHash,
            p_request_id: id,
          })
        : await serviceRpc<unknown>('admin_oauth_client_command', {
            p_actor_id: session.user_id,
            p_action: action,
            p_application_id: applicationId,
            p_client_id: targetId,
            p_provider: action === 'create' ? body.provider : null,
            p_external_client_id: action === 'create' ? body.externalClientId : null,
            p_client_type: action === 'create' ? body.clientType : null,
            p_environment: action === 'create' ? body.environment : null,
            p_name: action === 'create' ? body.name : null,
            p_reason: reason,
            p_idempotency_key: idempotencyKey,
            p_request_hash: requestHash,
            p_request_id: id,
          });
    if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') {
      return errorResponse(
        'INTERNAL_ERROR',
        'The Admin command returned an invalid result.',
        502,
        id,
      );
    }
    return jsonResponse(rows[0], action === 'create' ? 201 : 200, id);
  } catch (error) {
    return adminApplicationActionResponse(
      error,
      id,
      kind === 'membership' ? 'Application membership' : 'OAuth client',
    );
  }
}

export async function routePlatformAdmin(
  request: Request,
  health: (functionName: string) => Response = healthResponse,
): Promise<Response> {
  const id = requestIdFromRequest(request);
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
  if (path === '/v1/admin/overview') {
    return withCors(await adminOverviewRead(request, id), resolved);
  }
  const applicationMembershipsMatch = path.match(
    /^\/v1\/admin\/applications\/([^/]+)\/memberships$/,
  );
  if (applicationMembershipsMatch) {
    if (request.method === 'GET') {
      return withCors(
        await adminApplicationMembershipsRead(request, applicationMembershipsMatch[1], id),
        resolved,
      );
    }
    if (request.method === 'POST') {
      return withCors(
        await adminApplicationOperationCommand(
          request,
          'membership',
          'create',
          applicationMembershipsMatch[1],
          null,
          id,
        ),
        resolved,
      );
    }
  }
  const applicationOAuthClientsMatch = path.match(
    /^\/v1\/admin\/applications\/([^/]+)\/oauth-clients$/,
  );
  if (applicationOAuthClientsMatch) {
    if (request.method === 'GET') {
      return withCors(
        await adminOAuthClientsRead(request, applicationOAuthClientsMatch[1], id),
        resolved,
      );
    }
    if (request.method === 'POST') {
      return withCors(
        await adminApplicationOperationCommand(
          request,
          'oauth',
          'create',
          applicationOAuthClientsMatch[1],
          null,
          id,
        ),
        resolved,
      );
    }
  }
  const membershipCommandMatch = path.match(
    /^\/v1\/admin\/applications\/([^/]+)\/memberships\/([^/]+)\/(suspend|restore|delete)$/,
  );
  if (membershipCommandMatch) {
    return withCors(
      await adminApplicationOperationCommand(
        request,
        'membership',
        membershipCommandMatch[3] as 'suspend' | 'restore' | 'delete',
        membershipCommandMatch[1],
        membershipCommandMatch[2],
        id,
      ),
      resolved,
    );
  }
  const oauthCommandMatch = path.match(
    /^\/v1\/admin\/applications\/([^/]+)\/oauth-clients\/([^/]+)\/(disable|restore)$/,
  );
  if (oauthCommandMatch) {
    return withCors(
      await adminApplicationOperationCommand(
        request,
        'oauth',
        oauthCommandMatch[3] as 'disable' | 'restore',
        oauthCommandMatch[1],
        oauthCommandMatch[2],
        id,
      ),
      resolved,
    );
  }
  const productOverviewMatch = path.match(/^\/v1\/admin\/products\/([^/]+)\/overview$/);
  if (productOverviewMatch) {
    return withCors(await adminProductOverviewRead(request, productOverviewMatch[1], id), resolved);
  }
  const userOverviewMatch = path.match(/^\/v1\/admin\/users\/([^/]+)\/overview$/);
  if (userOverviewMatch) {
    return withCors(await adminUserOverviewRead(request, userOverviewMatch[1], id), resolved);
  }
  const orderOverviewMatch = path.match(/^\/v1\/admin\/orders\/([^/]+)\/overview$/);
  if (orderOverviewMatch) {
    return withCors(await adminOrderOverviewRead(request, orderOverviewMatch[1], id), resolved);
  }
  const redemptionRoute = redemptionCommandRoute(request, path);
  if (redemptionRoute) {
    return withCors(await adminRedemptionCommand(request, redemptionRoute, id), resolved);
  }
  const orderRoute = orderCommandRoute(request, path);
  if (orderRoute) {
    return withCors(await adminOrderCommand(request, orderRoute, id), resolved);
  }
  const orderItemRoute = orderItemCommandRoute(request, path);
  if (orderItemRoute) {
    return withCors(await adminOrderItemCommand(request, orderItemRoute, id), resolved);
  }
  const customerRoute = customerCommandRoute(request, path);
  if (customerRoute) {
    return withCors(await adminCustomerCommand(request, customerRoute, id), resolved);
  }
  const commandRoute = catalogCommandRoute(request, path);
  if (commandRoute) {
    return withCors(await adminCatalogCommand(request, commandRoute, id), resolved);
  }
  const draftRoute = draftMutationRoute(request, path);
  if (draftRoute) {
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
    /^\/v1\/admin\/(applications|users|origins|features|products|product-versions|prices|redemption-batches|redemption-codes|entitlements|redemptions|feedback|account-deletion-requests|audit-logs|orders|payments)$/,
  );
  if (queryMatch) {
    return withCors(await adminQueryRead(request, queryMatch[1], id), resolved);
  }

  return withCors(
    errorResponse('VALIDATION_ERROR', 'The requested route was not found.', 404, id),
    resolved,
  );
}
