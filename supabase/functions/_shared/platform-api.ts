import { healthResponse } from './health.ts';

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

const apiUrl = () => Deno.env.get('SUPABASE_URL') ?? 'http://127.0.0.1:54321';
const anonKey = () => Deno.env.get('SUPABASE_ANON_KEY');

function requestId(): string {
  return crypto.randomUUID();
}

function jsonResponse(
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

function errorResponse(code: string, message: string, status: number, id: string): Response {
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

function apiPath(request: Request): string {
  const pathname = new URL(request.url).pathname;
  const marker = pathname.indexOf('/v1/');
  return marker >= 0 ? pathname.slice(marker) : pathname;
}

async function rpc<T>(name: string, body: Record<string, unknown>, token?: string): Promise<T[]> {
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

function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}

async function sha256Hex(value: string): Promise<string> {
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

export async function routePlatformApi(request: Request): Promise<Response> {
  const id = requestId();
  const path = apiPath(request);

  if (path === '/' || path === '') return healthResponse('platform-api');
  if (path === '/v1/session/exchange') {
    if (request.method !== 'POST') {
      return errorResponse('VALIDATION_ERROR', 'Only POST requests are supported.', 405, id);
    }
    return sessionExchange(bearerToken(request), id);
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
