import { healthResponse } from './health.ts';
import { hashRedemptionCode, redemptionPepperFromEnv } from './redemption-code.ts';
import {
  applicationContextErrorResponse,
  type ApplicationContextKernel,
} from './auth/application-context.ts';
import { createPlatformApplicationContextKernel } from './auth/platform-context.ts';

type PublicApp = {
  readonly slug: string;
  readonly name: string;
  readonly category: string;
  readonly status: 'active';
};

type ProfileIdentity = {
  readonly userId: string;
  readonly displayName: string | null;
  readonly avatarUrl: string | null;
  readonly locale: string | null;
  readonly status: 'active' | 'disabled' | 'deletion_pending' | 'deleted';
};

type ResolvedOriginRow = {
  readonly app_slug: string;
  readonly environment: string;
};

type ResolvedOrigin = {
  readonly origin: string;
  readonly appSlug: string;
};

const allowedCorsMethods = new Set(['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS']);
const allowedCorsHeaders = new Set(['authorization', 'content-type', 'idempotency-key']);

const apiUrl = () => Deno.env.get('SUPABASE_URL') ?? 'http://127.0.0.1:54321';
const anonKey = () => Deno.env.get('SUPABASE_ANON_KEY');
const serviceRoleKey = () => Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

export function requestId(): string {
  return crypto.randomUUID();
}

export function requestIdFromRequest(request: Request): string {
  const value = request.headers.get('x-request-id')?.trim() ?? '';
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value
    : requestId();
}

export function jsonResponse(
  data: unknown,
  status: number,
  id: string,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify({ data, requestId: id }), {
    status,
    headers: {
      'content-type': 'application/json',
      'x-request-id': id,
      ...headers,
    },
  });
}

export function errorResponse(code: string, message: string, status: number, id: string): Response {
  return new Response(
    JSON.stringify({
      error: {
        code,
        message,
        requestId: id,
      },
    }),
    {
      status,
      headers: {
        'content-type': 'application/json',
        'x-request-id': id,
      },
    },
  );
}

export function bearerToken(request: Request): string | null {
  const value = request.headers.get('authorization');
  if (!value?.startsWith('Bearer ')) return null;
  const token = value.slice('Bearer '.length).trim();
  return token === '' ? null : token;
}

function isResolvedOrigin(value: unknown): value is ResolvedOriginRow {
  if (!value || typeof value !== 'object') return false;
  const origin = value as Record<string, unknown>;
  return (
    typeof origin.app_slug === 'string' &&
    /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(origin.app_slug) &&
    typeof origin.environment === 'string'
  );
}

export async function resolveOrigin(
  request: Request,
  id: string,
): Promise<ResolvedOrigin | Response | null> {
  const origin = request.headers.get('origin');

  if (origin === null) {
    return null;
  }

  try {
    const rows = await rpc<Record<string, unknown>>('resolve_app_origin', { p_origin: origin });
    const resolved = rows.length === 1 && isResolvedOrigin(rows[0]) ? rows[0] : null;
    if (!resolved) {
      return errorResponse('ORIGIN_NOT_ALLOWED', 'The request Origin is not allowed.', 403, id);
    }
    return { origin, appSlug: resolved.app_slug };
  } catch {
    return errorResponse('INTERNAL_ERROR', 'The request Origin could not be resolved.', 502, id);
  }
}

export function withCors(response: Response, resolved: ResolvedOrigin | null): Response {
  if (!resolved) return response;

  const headers = new Headers(response.headers);
  headers.set('access-control-allow-origin', resolved.origin);
  headers.set('access-control-allow-credentials', 'true');
  const vary = headers.get('vary');
  if (!vary) headers.set('vary', 'Origin');
  else if (!vary.split(',').some((value) => value.trim().toLowerCase() === 'origin')) {
    headers.set('vary', `${vary}, Origin`);
  }

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export function preflightResponse(
  request: Request,
  id: string,
  resolved: ResolvedOrigin,
): Response {
  const requestedMethod = request.headers.get('access-control-request-method');
  if (requestedMethod && !allowedCorsMethods.has(requestedMethod.toUpperCase())) {
    return withCors(
      errorResponse('VALIDATION_ERROR', 'The requested CORS method is not allowed.', 405, id),
      resolved,
    );
  }

  const requestedHeaders = request.headers.get('access-control-request-headers');
  if (requestedHeaders) {
    const unsupported = requestedHeaders
      .split(',')
      .map((header) => header.trim().toLowerCase())
      .filter((header) => header !== '' && !allowedCorsHeaders.has(header));
    if (unsupported.length > 0) {
      return withCors(
        errorResponse('VALIDATION_ERROR', 'The requested CORS header is not allowed.', 400, id),
        resolved,
      );
    }
  }

  return withCors(
    new Response(null, {
      status: 204,
      headers: {
        'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS',
        'access-control-allow-headers': 'Authorization, Content-Type, Idempotency-Key',
        'access-control-max-age': '600',
        'x-request-id': id,
      },
    }),
    resolved,
  );
}

export function apiPath(request: Request): string {
  const pathname = new URL(request.url).pathname;
  const marker = pathname.lastIndexOf('/v1/');
  return marker >= 0 ? pathname.slice(marker) : pathname;
}

export async function rpc<T>(
  name: string,
  body: Record<string, unknown>,
  token?: string,
): Promise<T[]> {
  const key = anonKey();
  if (!key) throw new Error('Supabase anon key is not configured.');

  const headers = new Headers({
    apikey: key,
    'content-type': 'application/json',
    accept: 'application/json',
  });
  if (token) headers.set('authorization', `Bearer ${token}`);

  const response = await fetch(`${apiUrl()}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error('Supabase read entry failed.');

  const value: unknown = await response.json();
  if (Array.isArray(value)) return value as T[];
  if (value && typeof value === 'object') return [value as T];
  throw new Error('Supabase read entry returned an invalid shape.');
}

export class ServiceRpcError extends Error {
  readonly databaseCode: string | undefined;

  constructor(databaseCode?: string) {
    super('The server data operation failed.');
    this.name = 'ServiceRpcError';
    this.databaseCode = databaseCode;
  }
}

export async function serviceRpc<T>(name: string, body: Record<string, unknown>): Promise<T[]> {
  const key = serviceRoleKey();
  if (!key) throw new Error('Supabase service role key is not configured.');

  const response = await fetch(`${apiUrl()}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    let databaseCode: string | undefined;
    try {
      const payload: unknown = await response.json();
      if (payload && typeof payload === 'object' && 'code' in payload) {
        databaseCode = typeof payload.code === 'string' ? payload.code : undefined;
      }
    } catch {
      // Deliberately discard upstream error details.
    }
    throw new ServiceRpcError(databaseCode);
  }

  const value: unknown = await response.json();
  if (Array.isArray(value)) return value as T[];
  if (value && typeof value === 'object') return [value as T];
  throw new Error('The server data operation returned an invalid shape.');
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function isPublicApp(value: unknown): value is PublicApp {
  if (!value || typeof value !== 'object') return false;
  const app = value as Record<string, unknown>;
  return (
    typeof app.slug === 'string' &&
    typeof app.name === 'string' &&
    typeof app.category === 'string' &&
    app.status === 'active'
  );
}

function isProfileIdentity(value: unknown): value is ProfileIdentity {
  if (!value || typeof value !== 'object') return false;
  const profile = value as Record<string, unknown>;
  const userId = typeof profile.userId === 'string' ? profile.userId : profile.id;
  return (
    typeof userId === 'string' &&
    (typeof profile.displayName === 'string' || profile.displayName === null) &&
    (typeof profile.avatarUrl === 'string' || profile.avatarUrl === null) &&
    (typeof profile.locale === 'string' || profile.locale === null) &&
    ['active', 'disabled', 'deletion_pending', 'deleted'].includes(String(profile.status))
  );
}

function toProfileIdentity(value: unknown): ProfileIdentity | null {
  if (!value || typeof value !== 'object') return null;
  const row = value as Record<string, unknown>;
  const profile = {
    userId: typeof row.userId === 'string' ? row.userId : row.id,
    displayName: row.displayName ?? row.display_name,
    avatarUrl: row.avatarUrl ?? row.avatar_url,
    locale: row.locale,
    status: row.status,
  };
  if (!isProfileIdentity(profile)) return null;
  return {
    userId: profile.userId,
    displayName: profile.displayName,
    avatarUrl: profile.avatarUrl,
    locale: profile.locale,
    status: profile.status,
  };
}

async function appRead(slug: string, id: string): Promise<Response> {
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) {
    return errorResponse('APP_NOT_FOUND', 'Application was not found.', 404, id);
  }

  try {
    const rows = await rpc<PublicApp>('get_public_app', { app_slug: slug });
    const app = rows.length === 1 && isPublicApp(rows[0]) ? rows[0] : null;
    return app
      ? jsonResponse({ app }, 200, id)
      : errorResponse('APP_NOT_FOUND', 'Application was not found.', 404, id);
  } catch {
    return errorResponse('INTERNAL_ERROR', 'The application could not be read.', 502, id);
  }
}

async function authenticatedProfileRead(
  token: string,
  userId: string,
  id: string,
): Promise<Response> {
  try {
    const rows = await rpc<ProfileIdentity>('current_profile', {}, token);
    const profile = rows.length === 1 ? toProfileIdentity(rows[0]) : null;
    if (!profile || profile.userId !== userId) {
      return errorResponse('PROFILE_NOT_FOUND', 'Profile was not found.', 404, id);
    }
    return jsonResponse({ profile }, 200, id);
  } catch {
    return errorResponse('INTERNAL_ERROR', 'The profile could not be read.', 502, id);
  }
}

let applicationContextKernel: ApplicationContextKernel | null = null;

function getApplicationContextKernel(): ApplicationContextKernel {
  return (applicationContextKernel ??= createPlatformApplicationContextKernel());
}

type ApplicationMembershipProjection = {
  readonly id: string;
  readonly application_id: string;
  readonly application_slug: string;
  readonly application_name: string;
  readonly application_category: string;
  readonly application_status: string;
  readonly registration_policy: string;
  readonly membership_policy: string;
  readonly default_locale: string | null;
  readonly membership_status: string;
  readonly created_source: string;
  readonly joined_at: string;
  readonly activated_at: string | null;
  readonly suspended_at: string | null;
  readonly left_at: string | null;
  readonly deleted_at: string | null;
};

function isApplicationMembershipProjection(
  value: unknown,
): value is ApplicationMembershipProjection {
  if (!value || typeof value !== 'object') return false;
  const row = value as Record<string, unknown>;
  return (
    typeof row.id === 'string' &&
    typeof row.application_id === 'string' &&
    typeof row.application_slug === 'string' &&
    typeof row.application_name === 'string' &&
    typeof row.application_category === 'string' &&
    typeof row.application_status === 'string' &&
    typeof row.registration_policy === 'string' &&
    typeof row.membership_policy === 'string' &&
    (typeof row.default_locale === 'string' || row.default_locale === null) &&
    typeof row.membership_status === 'string' &&
    typeof row.created_source === 'string' &&
    typeof row.joined_at === 'string' &&
    (typeof row.activated_at === 'string' || row.activated_at === null) &&
    (typeof row.suspended_at === 'string' || row.suspended_at === null) &&
    (typeof row.left_at === 'string' || row.left_at === null) &&
    (typeof row.deleted_at === 'string' || row.deleted_at === null)
  );
}

async function accountApplicationsRead(userId: string, id: string): Promise<Response> {
  try {
    const rows = await serviceRpc<ApplicationMembershipProjection>(
      'list_user_application_memberships',
      { p_user_id: userId },
    );
    if (!rows.every(isApplicationMembershipProjection)) {
      return errorResponse('INTERNAL_ERROR', 'Applications could not be read.', 502, id);
    }
    return jsonResponse(
      {
        applications: rows.map((row) => ({
          id: row.id,
          userId,
          application: {
            id: row.application_id,
            slug: row.application_slug,
            name: row.application_name,
            category: row.application_category,
            status: row.application_status,
            registrationPolicy: row.registration_policy,
            membershipPolicy: row.membership_policy,
            defaultLocale: row.default_locale,
          },
          status: row.membership_status,
          createdSource: row.created_source,
          joinedAt: row.joined_at,
          activatedAt: row.activated_at,
          suspendedAt: row.suspended_at,
          leftAt: row.left_at,
          deletedAt: row.deleted_at,
        })),
      },
      200,
      id,
    );
  } catch {
    return errorResponse('INTERNAL_ERROR', 'Applications could not be read.', 502, id);
  }
}

async function applicationMembershipLeave(
  request: Request,
  userId: string,
  membershipId: string,
  expectedMembershipId: string,
  id: string,
): Promise<Response> {
  if (membershipId !== expectedMembershipId) {
    return errorResponse(
      'APP_ACCESS_DENIED',
      'The membership does not belong to this application.',
      403,
      id,
    );
  }
  const body = await parseJsonObject(request);
  const reason = typeof body?.reason === 'string' ? body.reason.trim() : '';
  const idempotencyKey = request.headers.get('idempotency-key')?.trim() ?? '';
  if (
    reason === '' ||
    reason.length > 1000 ||
    idempotencyKey === '' ||
    idempotencyKey.length > 255
  ) {
    return errorResponse('VALIDATION_ERROR', 'A reason and Idempotency-Key are required.', 400, id);
  }
  try {
    const rows = await serviceRpc<Record<string, unknown>>('application_membership_command', {
      p_actor_id: userId,
      p_action: 'leave',
      p_membership_id: membershipId,
      p_reason: reason,
      p_idempotency_key: idempotencyKey,
      p_request_hash: await sha256Hex(JSON.stringify({ membershipId, reason })),
      p_request_id: id,
    });
    const result = rows.length === 1 ? rows[0] : null;
    if (!result)
      return errorResponse('INTERNAL_ERROR', 'The membership command returned no result.', 502, id);
    return jsonResponse(result, 200, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === '42501') {
      return errorResponse('APP_ACCESS_DENIED', 'The membership command is not allowed.', 403, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '23514') {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'The membership cannot be left in its current state.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0001') {
      return errorResponse('IDEMPOTENCY_KEY_REUSED', 'The request key was already used.', 409, id);
    }
    return errorResponse(
      'INTERNAL_ERROR',
      'The membership command could not be completed.',
      502,
      id,
    );
  }
}

async function applicationEntitlementsRead(
  userId: string,
  applicationId: string,
  id: string,
): Promise<Response> {
  try {
    const rows = await serviceRpc<{
      readonly feature: string;
      readonly value: unknown;
      readonly source_product: string;
      readonly expires_at: string | null;
    }>('list_user_application_entitlements', {
      p_user_id: userId,
      p_application_id: applicationId,
    });
    return jsonResponse(
      {
        entitlements: rows.map((row) => ({
          feature: row.feature,
          value: row.value,
          sourceProduct: row.source_product,
          expiresAt: row.expires_at,
        })),
      },
      200,
      id,
    );
  } catch {
    return errorResponse('INTERNAL_ERROR', 'Entitlements could not be read.', 502, id);
  }
}

async function applicationAccessRead(
  userId: string,
  applicationId: string,
  featureCode: string,
  id: string,
): Promise<Response> {
  if (!/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/.test(featureCode)) {
    return errorResponse('VALIDATION_ERROR', 'The feature code is invalid.', 400, id);
  }
  try {
    const rows = await serviceRpc<AccessRow>('check_application_access', {
      p_user_id: userId,
      p_application_id: applicationId,
      p_feature_code: featureCode,
    });
    const row = rows.length === 1 ? rows[0] : null;
    if (!row) return errorResponse('INTERNAL_ERROR', 'Access could not be resolved.', 502, id);
    return jsonResponse(
      {
        allowed: row.allowed,
        feature: row.feature,
        value: row.value,
        sourceProduct: row.source_product,
        expiresAt: row.expires_at,
        decisionId: row.decision_id,
      },
      200,
      id,
    );
  } catch {
    return errorResponse('INTERNAL_ERROR', 'Access could not be resolved.', 502, id);
  }
}

async function applicationRedemptionCreate(
  request: Request,
  userId: string,
  applicationId: string,
  id: string,
): Promise<Response> {
  const idempotencyKey = request.headers.get('idempotency-key')?.trim() ?? '';
  const body = await parseJsonObject(request);
  const code = typeof body?.code === 'string' ? body.code.trim().toUpperCase() : '';
  if (idempotencyKey === '' || idempotencyKey.length > 255 || code === '' || code.length > 512) {
    return errorResponse('VALIDATION_ERROR', 'A code and Idempotency-Key are required.', 400, id);
  }
  try {
    const { pepper } = redemptionPepperFromEnv((name) => Deno.env.get(name));
    const codeHash = await hashRedemptionCode(code, pepper);
    const rows = await serviceRpc<{
      readonly redemption_id: string;
      readonly grant_id: string;
      readonly status: 'redeemed';
    }>('redeem_application_code', {
      p_code_hash: codeHash,
      p_user_id: userId,
      p_application_id: applicationId,
      p_idempotency_key: idempotencyKey,
      p_request_hash: await sha256Hex(JSON.stringify({ userId, applicationId, codeHash })),
    });
    const row = rows.length === 1 ? rows[0] : null;
    if (!row)
      return errorResponse('INTERNAL_ERROR', 'The redemption could not be completed.', 502, id);
    return jsonResponse(
      { redemptionId: row.redemption_id, grantId: row.grant_id, status: row.status },
      200,
      id,
    );
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === '23505') {
      return errorResponse('IDEMPOTENCY_KEY_REUSED', 'The request key was already used.', 409, id);
    }
    return errorResponse('REDEMPTION_UNAVAILABLE', 'The redemption code is unavailable.', 409, id);
  }
}

async function applicationFeedbackCreate(
  request: Request,
  userId: string,
  applicationId: string,
  membershipId: string,
  id: string,
): Promise<Response> {
  const body = await parseJsonObject(request);
  const kind = typeof body?.kind === 'string' ? body.kind.trim() : '';
  const title = typeof body?.title === 'string' ? body.title.trim() : '';
  const content = typeof body?.content === 'string' ? body.content.trim() : '';
  if (
    kind === '' ||
    kind.length > 50 ||
    title === '' ||
    title.length > 200 ||
    content === '' ||
    content.length > 20_000
  ) {
    return errorResponse('VALIDATION_ERROR', 'Feedback fields are required.', 400, id);
  }
  try {
    const rows = await serviceRpc<{
      readonly id: string;
      readonly status: 'open' | 'in_progress' | 'resolved' | 'closed';
      readonly created_at: string;
    }>('create_application_feedback', {
      p_application_id: applicationId,
      p_user_id: userId,
      p_membership_id: membershipId,
      p_kind: kind,
      p_title: title,
      p_content: content,
    });
    const row = rows.length === 1 ? rows[0] : null;
    if (!row) return errorResponse('INTERNAL_ERROR', 'Feedback could not be created.', 502, id);
    return jsonResponse({ id: row.id, status: row.status, createdAt: row.created_at }, 201, id);
  } catch {
    return errorResponse('INTERNAL_ERROR', 'Feedback could not be created.', 502, id);
  }
}

async function applicationAccountDeletionCreate(
  request: Request,
  userId: string,
  id: string,
): Promise<Response> {
  const body = await parseJsonObject(request);
  if (!body || Object.keys(body).length !== 0) {
    return errorResponse('VALIDATION_ERROR', 'The deletion request body must be empty.', 400, id);
  }
  const idempotencyKey = request.headers.get('idempotency-key')?.trim() ?? '';
  if (idempotencyKey === '' || idempotencyKey.length > 255) {
    return errorResponse('VALIDATION_ERROR', 'A valid Idempotency-Key is required.', 400, id);
  }
  try {
    const rows = await serviceRpc<AccountDeletionRow>('request_account_deletion', {
      p_user_id: userId,
      p_idempotency_key: idempotencyKey,
      p_request_hash: await sha256Hex(JSON.stringify({ operation: 'account-deletion', userId })),
      p_request_id: id,
    });
    const row = rows.length === 1 && isAccountDeletionRow(rows[0]) ? rows[0] : null;
    if (!row) return errorResponse('INTERNAL_ERROR', 'The deletion request is invalid.', 502, id);
    return jsonResponse(accountDeletionPayload(row), 202, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0001') {
      return errorResponse('IDEMPOTENCY_KEY_REUSED', 'The request key was already used.', 409, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '23505') {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'An account deletion request is already open.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0002') {
      return errorResponse('PROFILE_NOT_FOUND', 'The account profile was not found.', 404, id);
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '23514') {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'The account cannot request deletion in its current state.',
        409,
        id,
      );
    }
    return errorResponse('INTERNAL_ERROR', 'The deletion request could not be created.', 502, id);
  }
}

async function applicationAccountDeletionCancel(userId: string, id: string): Promise<Response> {
  try {
    const rows = await serviceRpc<AccountDeletionRow>('cancel_account_deletion', {
      p_user_id: userId,
      p_request_id: id,
    });
    const row = rows.length === 1 && isAccountDeletionRow(rows[0]) ? rows[0] : null;
    if (!row)
      return errorResponse('INTERNAL_ERROR', 'The cancellation response is invalid.', 502, id);
    return jsonResponse(accountDeletionPayload(row), 200, id);
  } catch (error) {
    if (error instanceof ServiceRpcError && error.databaseCode === 'P0002') {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'There is no account deletion request to cancel.',
        409,
        id,
      );
    }
    if (error instanceof ServiceRpcError && error.databaseCode === '23514') {
      return errorResponse(
        'INVALID_STATE_TRANSITION',
        'The account deletion request cannot be cancelled in its current state.',
        409,
        id,
      );
    }
    return errorResponse('INTERNAL_ERROR', 'The deletion request could not be cancelled.', 502, id);
  }
}

type AccountDeletionRow = {
  readonly deletion_request_id: string;
  readonly status: 'pending' | 'processing' | 'completed' | 'failed' | 'cancelled';
  readonly execute_after: string;
  readonly requested_at: string;
  readonly completed_at: string | null;
};

export async function parseJsonObject(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const value: unknown = await request.json();
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

type AccessRow = {
  readonly allowed: boolean;
  readonly feature: string;
  readonly value: unknown;
  readonly source_product: string | null;
  readonly expires_at: string | null;
  readonly decision_id: string;
};

function isAccountDeletionRow(value: unknown): value is AccountDeletionRow {
  if (!value || typeof value !== 'object') return false;
  const row = value as Record<string, unknown>;
  return (
    typeof row.deletion_request_id === 'string' &&
    ['pending', 'processing', 'completed', 'failed', 'cancelled'].includes(String(row.status)) &&
    typeof row.execute_after === 'string' &&
    typeof row.requested_at === 'string' &&
    (typeof row.completed_at === 'string' || row.completed_at === null)
  );
}

function accountDeletionPayload(row: AccountDeletionRow) {
  return {
    deletionRequestId: row.deletion_request_id,
    status: row.status,
    executeAfter: row.execute_after,
    requestedAt: row.requested_at,
    completedAt: row.completed_at,
  };
}

async function routePlatformApiRoutes(request: Request, id: string): Promise<Response> {
  const path = apiPath(request);

  if (path === '/' || path === '') return healthResponse('platform-api');
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }

  if (path.startsWith('/v1/apps/')) {
    const slug = decodeURIComponent(path.slice('/v1/apps/'.length));
    return appRead(slug, id);
  }
  return errorResponse('VALIDATION_ERROR', 'The requested route was not found.', 404, id);
}

async function routeApplicationApiRoutes(request: Request, id: string): Promise<Response> {
  let context: Awaited<ReturnType<ApplicationContextKernel['authenticate']>>;
  try {
    context = await getApplicationContextKernel().authenticate(request, id);
  } catch (error) {
    return (
      applicationContextErrorResponse(error, id) ??
      errorResponse('INTERNAL_ERROR', 'The application context could not be resolved.', 502, id)
    );
  }

  const path = apiPath(request);
  const token = bearerToken(request);
  if (!token)
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);

  if (path === '/v1/app/context') {
    if (request.method !== 'GET') {
      return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
    }
    return jsonResponse(
      {
        userId: context.userId,
        clientId: context.clientId,
        application: { id: context.applicationId, slug: context.applicationSlug },
        membershipId: context.membershipId,
        membershipStatus: context.membershipStatus,
        aal: context.aal,
      },
      200,
      id,
    );
  }
  if (path === '/v1/account/me' || path === '/v1/app/me') {
    if (request.method !== 'GET') {
      return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
    }
    return authenticatedProfileRead(token, context.userId, id);
  }
  if (path === '/v1/account/applications') {
    if (request.method !== 'GET') {
      return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
    }
    return accountApplicationsRead(context.userId, id);
  }
  const leaveMembershipMatch = path.match(/^\/v1\/account\/applications\/([^/]+)\/leave$/);
  if (leaveMembershipMatch) {
    if (request.method !== 'POST') {
      return errorResponse('VALIDATION_ERROR', 'Only POST requests are supported.', 405, id);
    }
    return applicationMembershipLeave(
      request,
      context.userId,
      decodeURIComponent(leaveMembershipMatch[1]),
      context.membershipId,
      id,
    );
  }
  if (path === '/v1/account/deletion-requests') {
    if (request.method === 'POST') {
      return applicationAccountDeletionCreate(request, context.userId, id);
    }
    if (request.method === 'DELETE') {
      return applicationAccountDeletionCancel(context.userId, id);
    }
    return errorResponse(
      'VALIDATION_ERROR',
      'Only POST and DELETE requests are supported.',
      405,
      id,
    );
  }
  if (path === '/v1/app/entitlements') {
    if (request.method !== 'GET') {
      return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
    }
    return applicationEntitlementsRead(context.userId, context.applicationId, id);
  }
  if (path.startsWith('/v1/app/access/')) {
    if (request.method !== 'GET') {
      return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
    }
    return applicationAccessRead(
      context.userId,
      context.applicationId,
      decodeURIComponent(path.slice('/v1/app/access/'.length)),
      id,
    );
  }
  if (path === '/v1/app/redemptions') {
    if (request.method !== 'POST') {
      return errorResponse('VALIDATION_ERROR', 'Only POST requests are supported.', 405, id);
    }
    return applicationRedemptionCreate(request, context.userId, context.applicationId, id);
  }
  if (path === '/v1/app/feedback') {
    if (request.method !== 'POST') {
      return errorResponse('VALIDATION_ERROR', 'Only POST requests are supported.', 405, id);
    }
    return applicationFeedbackCreate(
      request,
      context.userId,
      context.applicationId,
      context.membershipId,
      id,
    );
  }
  return errorResponse('VALIDATION_ERROR', 'The requested route was not found.', 404, id);
}

export async function routePlatformApi(request: Request): Promise<Response> {
  const id = requestIdFromRequest(request);
  const resolved = await resolveOrigin(request, id);
  if (resolved instanceof Response) return resolved;
  if (request.method === 'OPTIONS') {
    return resolved
      ? preflightResponse(request, id, resolved)
      : errorResponse('ORIGIN_NOT_ALLOWED', 'A request Origin is required.', 403, id);
  }
  const path = apiPath(request);
  if (path.startsWith('/v1/account/') || path.startsWith('/v1/app/')) {
    return withCors(await routeApplicationApiRoutes(request, id), resolved);
  }
  return withCors(await routePlatformApiRoutes(request, id), resolved);
}
