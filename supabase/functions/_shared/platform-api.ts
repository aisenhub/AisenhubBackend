import { healthResponse } from './health.ts';
import { hashRedemptionCode, redemptionPepperFromEnv } from './redemption-code.ts';

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

type PlatformSession = {
  readonly session_id: string;
  readonly user_id: string;
  readonly expires_at: string;
  readonly display_name: string | null;
  readonly avatar_url: string | null;
  readonly locale: string | null;
  readonly profile_status: 'active';
};

type ResolvedOriginRow = {
  readonly app_slug: string;
  readonly environment: string;
};

type ResolvedOrigin = {
  readonly origin: string;
  readonly appSlug: string;
};

const allowedCorsMethods = new Set(['GET', 'POST', 'DELETE', 'OPTIONS']);
const allowedCorsHeaders = new Set([
  'authorization',
  'content-type',
  'x-aisenhub-app',
  'x-csrf-token',
  'idempotency-key',
]);
const writeMethods = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

const apiUrl = () => Deno.env.get('SUPABASE_URL') ?? 'http://127.0.0.1:54321';
const anonKey = () => Deno.env.get('SUPABASE_ANON_KEY');
const serviceRoleKey = () => Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

export function requestId(): string {
  return crypto.randomUUID();
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

function bearerToken(request: Request): string | null {
  const value = request.headers.get('authorization');
  if (!value?.startsWith('Bearer ')) return null;
  const token = value.slice('Bearer '.length).trim();
  return token === '' ? null : token;
}

export function sessionCookie(request: Request): string | null {
  const cookieHeader = request.headers.get('cookie');
  if (!cookieHeader) return null;

  for (const part of cookieHeader.split(';')) {
    const separator = part.indexOf('=');
    if (separator < 0 || part.slice(0, separator).trim() !== '__Host-aisenhub_session') {
      continue;
    }
    const value = part.slice(separator + 1).trim();
    return value === '' ? null : value;
  }
  return null;
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
  const declaration = request.headers.get('x-aisenhub-app');

  if (origin === null) {
    return declaration === null
      ? null
      : errorResponse(
          'APP_ORIGIN_MISMATCH',
          'The application declaration cannot be verified.',
          403,
          id,
        );
  }

  try {
    const rows = await rpc<Record<string, unknown>>('resolve_app_origin', { p_origin: origin });
    const resolved = rows.length === 1 && isResolvedOrigin(rows[0]) ? rows[0] : null;
    if (!resolved) {
      return errorResponse('ORIGIN_NOT_ALLOWED', 'The request Origin is not allowed.', 403, id);
    }
    if (declaration !== null && declaration !== resolved.app_slug) {
      return errorResponse(
        'APP_ORIGIN_MISMATCH',
        'The application declaration does not match the request Origin.',
        403,
        id,
      );
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
        'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
        'access-control-allow-headers':
          'Authorization, Content-Type, X-AisenHub-App, X-CSRF-Token, Idempotency-Key',
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

class ServiceRpcError extends Error {
  readonly databaseCode: string | undefined;

  constructor(databaseCode?: string) {
    super('The server data operation failed.');
    this.name = 'ServiceRpcError';
    this.databaseCode = databaseCode;
  }
}

async function serviceRpc<T>(name: string, body: Record<string, unknown>): Promise<T[]> {
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

function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function authenticatedUser(token: string): Promise<string | null> {
  const key = anonKey();
  if (!key) return null;

  const response = await fetch(`${apiUrl()}/auth/v1/user`, {
    headers: {
      apikey: key,
      authorization: `Bearer ${token}`,
    },
  });
  if (!response.ok) return null;

  const value: unknown = await response.json();
  if (!value || typeof value !== 'object' || !('id' in value)) return null;
  const id = value.id;
  return typeof id === 'string' && id.length > 0 ? id : null;
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

async function meRead(token: string | null, id: string): Promise<Response> {
  if (!token)
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);

  const userId = await authenticatedUser(token);
  if (!userId)
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);

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

async function sessionExchange(token: string | null, id: string): Promise<Response> {
  if (!token)
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);

  const userId = await authenticatedUser(token);
  if (!userId)
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);

  try {
    const profileRows = await rpc<ProfileIdentity>('current_profile', {}, token);
    const profile = profileRows.length === 1 ? toProfileIdentity(profileRows[0]) : null;
    if (!profile) return errorResponse('PROFILE_NOT_FOUND', 'Profile was not found.', 404, id);
    if (profile.status !== 'active') {
      return errorResponse('ACCOUNT_DISABLED', 'This account cannot create a session.', 403, id);
    }

    const sessionToken = randomToken();
    const csrfToken = randomToken();
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
    const rows = await rpc<{ readonly session_id: string; readonly expires_at: string }>(
      'create_platform_session',
      {
        p_user_id: userId,
        p_token_hash: await sha256Hex(sessionToken),
        p_csrf_hash: await sha256Hex(csrfToken),
        p_expires_at: expiresAt,
      },
      token,
    );
    if (rows.length !== 1 || typeof rows[0]?.session_id !== 'string') {
      return errorResponse('INTERNAL_ERROR', 'The session could not be created.', 502, id);
    }

    return jsonResponse(
      {
        authenticated: true,
        identity: profile,
        expiresAt,
        csrfToken,
      },
      201,
      id,
      {
        'set-cookie': `__Host-aisenhub_session=${sessionToken}; Max-Age=2592000; Path=/; Secure; HttpOnly; SameSite=Lax`,
      },
    );
  } catch {
    return errorResponse('INTERNAL_ERROR', 'The session could not be created.', 502, id);
  }
}

type SessionUserRow = {
  readonly user_id: string;
  readonly profile_status: 'active';
};

async function sessionUserId(request: Request): Promise<string | null> {
  const token = sessionCookie(request);
  if (!token) return null;

  const rows = await rpc<SessionUserRow>('get_platform_session', {
    p_token_hash: await sha256Hex(token),
  });
  if (rows.length !== 1 || rows[0]?.profile_status !== 'active') return null;
  return rows[0].user_id;
}

async function parseJsonObject(request: Request): Promise<Record<string, unknown> | null> {
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

async function accessRead(
  request: Request,
  featureCode: string,
  appSlug: string,
  id: string,
): Promise<Response> {
  const userId = await sessionUserId(request);
  if (!userId)
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  if (!/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/.test(featureCode)) {
    return errorResponse('VALIDATION_ERROR', 'The feature code is invalid.', 400, id);
  }

  try {
    const rows = await serviceRpc<AccessRow>('check_access', {
      p_user_id: userId,
      p_app_slug: appSlug,
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

async function entitlementsRead(request: Request, id: string): Promise<Response> {
  const userId = await sessionUserId(request);
  if (!userId)
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);

  try {
    const rows = await serviceRpc<{
      readonly feature: string;
      readonly value: unknown;
      readonly source_product: string;
      readonly expires_at: string | null;
    }>('list_user_entitlements', { p_user_id: userId });
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

async function redemptionCreate(request: Request, id: string): Promise<Response> {
  const userId = await sessionUserId(request);
  if (!userId)
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
  const idempotencyKey = request.headers.get('idempotency-key');
  const body = await parseJsonObject(request);
  const code = typeof body?.code === 'string' ? body.code.trim().toUpperCase() : '';
  const normalizedIdempotencyKey = idempotencyKey?.trim() ?? '';
  if (
    normalizedIdempotencyKey === '' ||
    normalizedIdempotencyKey.length > 255 ||
    code === '' ||
    code.length > 512
  ) {
    return errorResponse('VALIDATION_ERROR', 'A code and Idempotency-Key are required.', 400, id);
  }

  try {
    const { pepper } = redemptionPepperFromEnv((name) => Deno.env.get(name));
    const codeHash = await hashRedemptionCode(code, pepper);
    const requestHash = await sha256Hex(JSON.stringify({ userId, codeHash }));
    const rows = await serviceRpc<{
      readonly redemption_id: string;
      readonly grant_id: string;
      readonly status: 'redeemed';
    }>('redeem_code', {
      p_code_hash: codeHash,
      p_user_id: userId,
      p_idempotency_key: normalizedIdempotencyKey,
      p_request_hash: requestHash,
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

async function feedbackCreate(request: Request, id: string, appSlug: string): Promise<Response> {
  const userId = await sessionUserId(request);
  if (!userId)
    return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
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
    }>('create_feedback', {
      p_app_slug: appSlug,
      p_user_id: userId,
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

function isPlatformSession(value: unknown): value is PlatformSession {
  if (!value || typeof value !== 'object') return false;
  const session = value as Record<string, unknown>;
  return (
    typeof session.session_id === 'string' &&
    typeof session.user_id === 'string' &&
    typeof session.expires_at === 'string' &&
    (typeof session.display_name === 'string' || session.display_name === null) &&
    (typeof session.avatar_url === 'string' || session.avatar_url === null) &&
    (typeof session.locale === 'string' || session.locale === null) &&
    session.profile_status === 'active'
  );
}

function sessionIdentity(session: PlatformSession): ProfileIdentity {
  return {
    userId: session.user_id,
    displayName: session.display_name,
    avatarUrl: session.avatar_url,
    locale: session.locale,
    status: session.profile_status,
  };
}

function clearSessionCookie(): string {
  return '__Host-aisenhub_session=; Max-Age=0; Path=/; Secure; HttpOnly; SameSite=Lax';
}

async function sessionRead(request: Request, id: string): Promise<Response> {
  const rawToken = sessionCookie(request);
  if (!rawToken) {
    return jsonResponse({ authenticated: false, identity: null, expiresAt: null }, 200, id);
  }

  try {
    const rows = await rpc<PlatformSession>('get_platform_session', {
      p_token_hash: await sha256Hex(rawToken),
    });
    const session = rows.length === 1 && isPlatformSession(rows[0]) ? rows[0] : null;
    if (!session) {
      return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
    }

    const csrfToken = randomToken();
    const csrfRows = await rpc<{ readonly issued: boolean }>('rotate_platform_csrf', {
      p_token_hash: await sha256Hex(rawToken),
      p_csrf_hash: await sha256Hex(csrfToken),
    });
    if (csrfRows.length !== 1 || csrfRows[0]?.issued !== true) {
      return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required.', 401, id);
    }

    return jsonResponse(
      {
        authenticated: true,
        identity: sessionIdentity(session),
        expiresAt: session.expires_at,
        csrfToken,
      },
      200,
      id,
    );
  } catch {
    return errorResponse('INTERNAL_ERROR', 'The session could not be read.', 502, id);
  }
}

async function sessionDelete(request: Request, id: string): Promise<Response> {
  const rawToken = sessionCookie(request);
  try {
    if (rawToken) {
      await rpc<{ readonly revoked: boolean }>('revoke_platform_session', {
        p_token_hash: await sha256Hex(rawToken),
        p_reason: 'user_logout',
      });
    }
    return jsonResponse({ revoked: true }, 200, id, { 'set-cookie': clearSessionCookie() });
  } catch {
    return errorResponse('INTERNAL_ERROR', 'The session could not be revoked.', 502, id);
  }
}

async function enforceWritePreconditions(
  request: Request,
  path: string,
  resolved: ResolvedOrigin | null,
  id: string,
): Promise<Response | null> {
  if (!writeMethods.has(request.method) || path === '/v1/session/exchange') return null;
  if (!resolved) {
    return errorResponse('ORIGIN_NOT_ALLOWED', 'A request Origin is required.', 403, id);
  }
  if (request.headers.get('x-aisenhub-app') !== resolved.appSlug) {
    return errorResponse(
      'APP_ORIGIN_MISMATCH',
      'The application declaration does not match the request Origin.',
      403,
      id,
    );
  }

  const rawToken = sessionCookie(request);
  const rawCsrf = request.headers.get('x-csrf-token');
  if (!rawToken || !rawCsrf) {
    return errorResponse('CSRF_INVALID', 'A valid CSRF token is required.', 403, id);
  }

  try {
    const rows = await rpc<{ readonly valid: boolean }>('verify_platform_csrf', {
      p_token_hash: await sha256Hex(rawToken),
      p_csrf_hash: await sha256Hex(rawCsrf),
    });
    if (rows.length !== 1 || rows[0]?.valid !== true) {
      return errorResponse('CSRF_INVALID', 'A valid CSRF token is required.', 403, id);
    }
    return null;
  } catch {
    return errorResponse(
      'INTERNAL_ERROR',
      'The request security checks could not be completed.',
      502,
      id,
    );
  }
}

async function routePlatformApiRoutes(
  request: Request,
  id: string,
  resolved: ResolvedOrigin | null,
): Promise<Response> {
  const path = apiPath(request);

  if (path === '/' || path === '') return healthResponse('platform-api');
  if (path === '/v1/session/exchange') {
    if (request.method !== 'POST') {
      return errorResponse('VALIDATION_ERROR', 'Only POST requests are supported.', 405, id);
    }
    return sessionExchange(bearerToken(request), id);
  }
  if (path === '/v1/session') {
    if (request.method === 'GET') return sessionRead(request, id);
    if (request.method === 'DELETE') return sessionDelete(request, id);
    return errorResponse(
      'VALIDATION_ERROR',
      'Only GET and DELETE requests are supported.',
      405,
      id,
    );
  }
  if (path === '/v1/me/entitlements') {
    if (request.method !== 'GET') {
      return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
    }
    return entitlementsRead(request, id);
  }
  if (path.startsWith('/v1/access/')) {
    if (request.method !== 'GET') {
      return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
    }
    if (!resolved)
      return errorResponse('ORIGIN_NOT_ALLOWED', 'A request Origin is required.', 403, id);
    return accessRead(
      request,
      decodeURIComponent(path.slice('/v1/access/'.length)),
      resolved.appSlug,
      id,
    );
  }
  if (path === '/v1/redemptions') {
    if (request.method !== 'POST') {
      return errorResponse('VALIDATION_ERROR', 'Only POST requests are supported.', 405, id);
    }
    return redemptionCreate(request, id);
  }
  if (path === '/v1/feedback') {
    if (request.method !== 'POST') {
      return errorResponse('VALIDATION_ERROR', 'Only POST requests are supported.', 405, id);
    }
    if (!resolved)
      return errorResponse('ORIGIN_NOT_ALLOWED', 'A request Origin is required.', 403, id);
    return feedbackCreate(request, id, resolved.appSlug);
  }
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }

  if (path.startsWith('/v1/apps/')) {
    const slug = decodeURIComponent(path.slice('/v1/apps/'.length));
    return appRead(slug, id);
  }
  if (path === '/v1/me') return meRead(bearerToken(request), id);

  return errorResponse('VALIDATION_ERROR', 'The requested route was not found.', 404, id);
}

export async function routePlatformApi(request: Request): Promise<Response> {
  const id = requestId();
  const resolved = await resolveOrigin(request, id);
  if (resolved instanceof Response) return resolved;
  if (request.method === 'OPTIONS') {
    return resolved
      ? preflightResponse(request, id, resolved)
      : errorResponse('ORIGIN_NOT_ALLOWED', 'A request Origin is required.', 403, id);
  }
  const path = apiPath(request);
  const preconditionFailure = await enforceWritePreconditions(request, path, resolved, id);
  if (preconditionFailure) return withCors(preconditionFailure, resolved);
  return withCors(await routePlatformApiRoutes(request, id, resolved), resolved);
}
