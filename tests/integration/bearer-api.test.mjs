import { afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';

const apiOrigin = 'http://api.local';
const accountOrigin = 'http://localhost:5173';
const adminOrigin = 'http://localhost:5174';
const userId = '00000000-0000-4000-8000-000000000001';
const accountAppId = '20000000-0000-4000-8000-000000000002';
const adminAppId = '20000000-0000-4000-8000-000000000003';
const originalFetch = globalThis.fetch;

let keyPair;
let publicJwk;
let lastServiceCall;

function encode(value) {
  return btoa(JSON.stringify(value))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
}

function response(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

async function tokenFor(clientId, aal = 'aal1') {
  const header = encode({ alg: 'RS256', kid: 'integration-key', typ: 'JWT' });
  const now = Math.floor(Date.now() / 1000);
  const payload = encode({
    iss: `${apiOrigin}/auth/v1`,
    sub: userId,
    aud: 'authenticated',
    exp: now + 3600,
    iat: now,
    client_id: clientId,
    role: 'authenticated',
    aal,
  });
  const signature = await crypto.subtle.sign(
    { name: 'RSASSA-PKCS1-v1_5' },
    keyPair.privateKey,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '')}`;
}

function contextFor(clientId) {
  const isAdmin = clientId === 'admin-local-web';
  return [
    {
      user_id: userId,
      profile_status: 'active',
      client_id: clientId,
      client_status: 'active',
      application_id: isAdmin ? adminAppId : accountAppId,
      application_slug: isAdmin ? 'admin' : 'account',
      application_status: 'active',
      membership_id: `00000000-0000-4000-8000-${isAdmin ? '000000000003' : '000000000002'}`,
      membership_status: 'active',
      membership_policy: 'explicit',
    },
  ];
}

async function mockedFetch(url, init) {
  const parsedUrl = new URL(url);
  const pathname = parsedUrl.pathname;
  const body = JSON.parse(init?.body ?? '{}');
  if (url === `${apiOrigin}/auth/v1/.well-known/jwks.json`) {
    return response({ keys: [publicJwk] });
  }
  if (pathname.endsWith('/resolve_app_origin')) {
    const appSlug = body.p_origin === accountOrigin ? 'account' : body.p_origin === adminOrigin ? 'admin' : null;
    return response(appSlug ? [{ app_slug: appSlug, environment: 'development' }] : []);
  }
  if (pathname.endsWith('/resolve_application_context')) {
    return response(contextFor(body.p_client_id));
  }
  if (pathname.endsWith('/resolve_admin_membership')) {
    return response([{ user_id: userId, display_name: 'Local Admin', role: 'admin', status: 'active' }]);
  }
  if (pathname.endsWith('/current_profile')) {
    return response([{ userId, displayName: 'Account User', avatarUrl: null, locale: 'en-US', status: 'active' }]);
  }
  if (pathname.endsWith('/list_user_application_memberships')) return response([]);
  if (pathname.endsWith('/list_user_entitlements')) {
    lastServiceCall = { pathname, body };
    return response([{ feature: 'lens.export', value: { max: 10 }, source_product: 'AISENLENS_PRO', expires_at: null }]);
  }
  if (pathname.endsWith('/check_access')) {
    lastServiceCall = { pathname, body };
    return response([{ allowed: true, feature: body.p_feature_code, value: { max: 10 }, source_product: 'AISENLENS_PRO', expires_at: null, decision_id: '00000000-0000-4000-8000-000000000020' }]);
  }
  if (pathname.endsWith('/admin_query_resource')) {
    lastServiceCall = { pathname, body };
    return response([{ items: [{ id: '00000000-0000-4000-8000-000000000030', slug: 'admin', status: 'active' }], page: { hasMore: false, nextCursor: null } }]);
  }
  return response([]);
}

beforeAll(async () => {
  globalThis.Deno = { env: { get: (name) => ({
    SUPABASE_URL: apiOrigin,
    SUPABASE_ANON_KEY: 'anon-key',
    SUPABASE_SERVICE_ROLE_KEY: 'service-role-key',
  })[name] } };
  keyPair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  );
  publicJwk = Object.assign(await crypto.subtle.exportKey('jwk', keyPair.publicKey), {
    kid: 'integration-key', alg: 'RS256', use: 'sig',
  });
});

beforeEach(() => {
  globalThis.fetch = mockedFetch;
  lastServiceCall = null;
});

describe('Bearer application API', () => {
  it('resolves application context and profile from the verified client identity', async () => {
    const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
    const token = await tokenFor('account-local-web');
    const responseValue = await routePlatformApi(new Request(`${apiOrigin}/v1/app/context`, {
      headers: { Authorization: `Bearer ${token}`, Origin: accountOrigin },
    }));
    expect(responseValue.status).toBe(200);
    expect((await responseValue.json()).data.application.slug).toBe('account');
    expect(responseValue.headers.get('access-control-allow-origin')).toBe(accountOrigin);
  });

  it('allows no-Origin service requests but rejects a mismatched registered Origin', async () => {
    const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
    const token = await tokenFor('account-local-web');
    const withoutOrigin = await routePlatformApi(new Request(`${apiOrigin}/v1/app/context`, {
      headers: { Authorization: `Bearer ${token}` },
    }));
    expect(withoutOrigin.status).toBe(200);
    const mismatched = await routePlatformApi(new Request(`${apiOrigin}/v1/app/context`, {
      headers: { Authorization: `Bearer ${token}`, Origin: adminOrigin },
    }));
    expect(mismatched.status).toBe(403);
    expect((await mismatched.json()).error.code).toBe('ORIGIN_NOT_ALLOWED');
  });

  it('uses the verified application for access decisions and removes legacy routes', async () => {
    const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
    const token = await tokenFor('account-local-web');
    const access = await routePlatformApi(new Request(`${apiOrigin}/v1/app/access/lens.export`, {
      headers: { Authorization: `Bearer ${token}` },
    }));
    expect(access.status).toBe(200);
    expect(lastServiceCall.body.p_app_slug).toBe('account');
    const legacy = await routePlatformApi(new Request(`${apiOrigin}/v1/session`));
    expect(legacy.status).toBe(404);
  });
});

describe('Bearer Admin API', () => {
  it('reads Admin identity and queries without a Platform Session or CSRF token', async () => {
    const { routePlatformAdmin } = await import('../../supabase/functions/_shared/admin-api.ts');
    const token = await tokenFor('admin-local-web', 'aal2');
    const session = await routePlatformAdmin(new Request(`${apiOrigin}/v1/admin/session`, {
      headers: { Authorization: `Bearer ${token}`, Origin: adminOrigin },
    }));
    expect(session.status).toBe(200);
    expect((await session.json()).data).toMatchObject({ role: 'admin', aal: 'aal2', mfaState: 'verified' });
    const query = await routePlatformAdmin(new Request(`${apiOrigin}/v1/admin/applications?limit=10`, {
      headers: { Authorization: `Bearer ${token}` },
    }));
    expect(query.status).toBe(200);
    expect(lastServiceCall.body.p_actor_id).toBe(userId);
  });

  it('requires a bearer token and rejects the removed session route', async () => {
    const { routePlatformAdmin } = await import('../../supabase/functions/_shared/admin-api.ts');
    const missing = await routePlatformAdmin(new Request(`${apiOrigin}/v1/admin/applications`));
    expect(missing.status).toBe(401);
    const legacy = await routePlatformAdmin(new Request(`${apiOrigin}/v1/admin/session`, {
      headers: { Cookie: '__Host-aisenhub_session=legacy-token' },
    }));
    expect(legacy.status).toBe(401);
  });
});

afterEach(() => {
  globalThis.fetch = originalFetch;
});
