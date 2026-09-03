import { afterAll, afterEach, describe, expect, it, vi } from 'vitest';

const registeredOrigin = 'http://localhost:5173';
const originalFetch = globalThis.fetch;
let csrfIsValid = false;
let authUserIsValid = true;
let profileStatus = 'active';
let platformSessionIsValid = true;

async function rpcResponse(url, init) {
  const pathname = new URL(url).pathname;
  if (pathname.endsWith('/auth/v1/user')) {
    return authUserIsValid
      ? new Response(JSON.stringify({ id: '00000000-0000-4000-8000-000000000001' }), {
          headers: { 'content-type': 'application/json' },
        })
      : new Response(JSON.stringify({ error: 'invalid_token' }), { status: 401 });
  }
  if (pathname.endsWith('/resolve_app_origin')) {
    const body = JSON.parse(init?.body ?? '{}');
    const rows =
      body.p_origin === registeredOrigin
        ? [{ app_slug: 'account', environment: 'development' }]
        : [];
    return new Response(JSON.stringify(rows), {
      headers: { 'content-type': 'application/json' },
    });
  }
  if (pathname.endsWith('/get_public_app')) {
    return new Response(
      JSON.stringify([
        { slug: 'aisenlens', name: 'AisenLens', category: 'tool', status: 'active' },
      ]),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  if (pathname.endsWith('/verify_platform_csrf')) {
    return new Response(JSON.stringify([{ valid: csrfIsValid }]), {
      headers: { 'content-type': 'application/json' },
    });
  }
  if (pathname.endsWith('/get_platform_session')) {
    return new Response(
      JSON.stringify(
        platformSessionIsValid
          ? [
              {
                session_id: '00000000-0000-4000-8000-000000000010',
                user_id: '00000000-0000-4000-8000-000000000001',
                expires_at: '2026-10-01T00:00:00.000Z',
                display_name: 'Account User',
                avatar_url: null,
                locale: 'en-US',
                profile_status: 'active',
              },
            ]
          : [],
      ),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  if (pathname.endsWith('/current_profile')) {
    return new Response(
      JSON.stringify([
        {
          userId: '00000000-0000-4000-8000-000000000001',
          display_name: 'Account User',
          avatar_url: null,
          locale: 'en-US',
          status: profileStatus,
        },
      ]),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  if (pathname.endsWith('/create_platform_session')) {
    return new Response(
      JSON.stringify([
        {
          session_id: '00000000-0000-4000-8000-000000000010',
          expires_at: '2026-10-01T00:00:00.000Z',
        },
      ]),
      { headers: { 'content-type': 'application/json' } },
    );
  }
  if (pathname.endsWith('/rotate_platform_csrf')) {
    return new Response(JSON.stringify([{ issued: true }]), {
      headers: { 'content-type': 'application/json' },
    });
  }
  throw new Error(`Unexpected mocked RPC: ${pathname}`);
}

vi.stubGlobal('Deno', {
  env: {
    get(name) {
      return name === 'SUPABASE_URL' ? 'http://local.supabase' : 'local-anon-key';
    },
  },
});
vi.stubGlobal(
  'fetch',
  vi.fn(async (url, init) => rpcResponse(url, init)),
);

const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');

afterAll(() => {
  globalThis.fetch = originalFetch;
  vi.unstubAllGlobals();
});

afterEach(() => {
  authUserIsValid = true;
  profileStatus = 'active';
  platformSessionIsValid = true;
  csrfIsValid = false;
});

describe('platform API Origin and CORS handler', () => {
  it('echoes only a registered exact Origin with credentials', async () => {
    const response = await routePlatformApi(
      new Request('http://api.local/v1/apps/aisenlens', {
        headers: { Origin: registeredOrigin, 'X-AisenHub-App': 'account' },
      }),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get('access-control-allow-origin')).toBe(registeredOrigin);
    expect(response.headers.get('access-control-allow-credentials')).toBe('true');
    expect(response.headers.get('access-control-allow-origin')).not.toBe('*');
  });

  it('answers credentialed preflight with the exact registered Origin', async () => {
    const response = await routePlatformApi(
      new Request('http://api.local/v1/session', {
        method: 'OPTIONS',
        headers: {
          Origin: registeredOrigin,
          'Access-Control-Request-Method': 'DELETE',
          'Access-Control-Request-Headers': 'X-AisenHub-App, X-CSRF-Token',
        },
      }),
    );

    expect(response.status).toBe(204);
    expect(response.headers.get('access-control-allow-origin')).toBe(registeredOrigin);
    expect(response.headers.get('access-control-allow-credentials')).toBe('true');
  });

  it('rejects unregistered and wildcard Origins', async () => {
    const cases = [
      ['https://attacker.example'],
      ['*'],
    ];

    for (const [origin] of cases) {
      const headers = { Origin: origin };
      const response = await routePlatformApi(
        new Request('http://api.local/v1/apps/aisenlens', { headers }),
      );
      const body = await response.json();

      expect(response.status).toBe(403);
      expect(body.error.code).toBe('ORIGIN_NOT_ALLOWED');
      expect(response.headers.get('access-control-allow-origin')).toBeNull();
    }
  });

  it('does not add CORS authority when Origin is absent', async () => {
    const response = await routePlatformApi(new Request('http://api.local/v1/apps/aisenlens'));

    expect(response.status).toBe(200);
    expect(response.headers.get('access-control-allow-origin')).toBeNull();
  });

  it('bootstraps a fresh CSRF token without exposing its digest', async () => {
    const response = await routePlatformApi(
      new Request('http://api.local/v1/session', {
        headers: {
          Origin: registeredOrigin,
          Cookie: '__Host-aisenhub_session=session-token',
        },
      }),
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.authenticated).toBe(true);
    expect(typeof body.data.csrfToken).toBe('string');
    expect(body.data).not.toHaveProperty('csrfHash');
  });

  it('rejects mutations without a session-bound CSRF token', async () => {
    const missing = await routePlatformApi(
      new Request('http://api.local/v1/future-command', {
        method: 'POST',
        headers: { Origin: registeredOrigin, 'X-AisenHub-App': 'account' },
      }),
    );
    expect(missing.status).toBe(403);
    expect((await missing.json()).error.code).toBe('CSRF_INVALID');

    const wrong = await routePlatformApi(
      new Request('http://api.local/v1/future-command', {
        method: 'POST',
        headers: {
          Origin: registeredOrigin,
          'X-AisenHub-App': 'account',
          Cookie: '__Host-aisenhub_session=session-token',
          'X-CSRF-Token': 'wrong-token',
        },
      }),
    );
    expect(wrong.status).toBe(403);
    expect((await wrong.json()).error.code).toBe('CSRF_INVALID');

    csrfIsValid = true;
    const valid = await routePlatformApi(
      new Request('http://api.local/v1/future-command', {
        method: 'POST',
        headers: {
          Origin: registeredOrigin,
          'X-AisenHub-App': 'account',
          Cookie: '__Host-aisenhub_session=session-token',
          'X-CSRF-Token': 'valid-token',
        },
      }),
    );
    expect(valid.status).toBe(405);
    csrfIsValid = false;
  });

  it('requires a verified bearer and returns a hash-free session exchange', async () => {
    const missing = await routePlatformApi(
      new Request('http://api.local/v1/session/exchange', { method: 'POST' }),
    );
    expect(missing.status).toBe(401);
    expect((await missing.json()).error.code).toBe('AUTHENTICATION_REQUIRED');

    authUserIsValid = false;
    const invalid = await routePlatformApi(
      new Request('http://api.local/v1/session/exchange', {
        method: 'POST',
        headers: { Authorization: 'Bearer invalid' },
      }),
    );
    expect(invalid.status).toBe(401);
    expect((await invalid.json()).error.code).toBe('AUTHENTICATION_REQUIRED');

    authUserIsValid = true;
    const exchanged = await routePlatformApi(
      new Request('http://api.local/v1/session/exchange', {
        method: 'POST',
        headers: { Authorization: 'Bearer valid' },
      }),
    );
    const body = await exchanged.json();
    expect(exchanged.status).toBe(201);
    expect(body.data.authenticated).toBe(true);
    expect(body.data).not.toHaveProperty('tokenHash');
    expect(body.data).not.toHaveProperty('csrfHash');
    expect(exchanged.headers.get('set-cookie')).toMatch(
      /__Host-aisenhub_session=[^;]+; Max-Age=2592000; Path=\/; Secure; HttpOnly; SameSite=Lax/,
    );
    expect(exchanged.headers.get('set-cookie')).not.toContain('Domain=');
  });

  it('rejects disabled accounts during session exchange', async () => {
    profileStatus = 'disabled';
    const response = await routePlatformApi(
      new Request('http://api.local/v1/session/exchange', {
        method: 'POST',
        headers: { Authorization: 'Bearer valid' },
      }),
    );

    expect(response.status).toBe(403);
    const body = await response.json();
    expect(body.error.code).toBe('ACCOUNT_DISABLED');
    expect(JSON.stringify(body)).not.toMatch(/token_hash|csrf_hash|SQLSTATE|stack/i);
  });

  it('protects profile and session reads with stable errors', async () => {
    const missingMe = await routePlatformApi(new Request('http://api.local/v1/me'));
    expect(missingMe.status).toBe(401);
    expect((await missingMe.json()).error.code).toBe('AUTHENTICATION_REQUIRED');

    const me = await routePlatformApi(
      new Request('http://api.local/v1/me', { headers: { Authorization: 'Bearer valid' } }),
    );
    expect(me.status).toBe(200);
    expect((await me.json()).data.profile.userId).toBe('00000000-0000-4000-8000-000000000001');

    platformSessionIsValid = false;
    const expired = await routePlatformApi(
      new Request('http://api.local/v1/session', {
        headers: { Cookie: '__Host-aisenhub_session=expired-token' },
      }),
    );
    expect(expired.status).toBe(401);
    const expiredBody = await expired.json();
    expect(expiredBody.error.code).toBe('AUTHENTICATION_REQUIRED');
    expect(JSON.stringify(expiredBody)).not.toMatch(/token_hash|csrf_hash|SQLSTATE|stack/i);
  });

  it('enforces method boundaries with stable validation errors', async () => {
    const method = await routePlatformApi(
      new Request('http://api.local/v1/session/exchange', { method: 'GET' }),
    );
    expect(method.status).toBe(405);
    expect((await method.json()).error.code).toBe('VALIDATION_ERROR');

    const route = await routePlatformApi(new Request('http://api.local/v1/unknown'));
    expect(route.status).toBe(404);
    expect((await route.json()).error.code).toBe('VALIDATION_ERROR');
  });
});
