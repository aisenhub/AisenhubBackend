import { afterAll, describe, expect, it, vi } from 'vitest';

const registeredOrigin = 'http://localhost:5173';
const originalFetch = globalThis.fetch;

async function rpcResponse(url, init) {
  const pathname = new URL(url).pathname;
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

  it('rejects unregistered, wildcard, and mismatched app declarations', async () => {
    const cases = [
      ['https://attacker.example', undefined, 'ORIGIN_NOT_ALLOWED'],
      ['*', undefined, 'ORIGIN_NOT_ALLOWED'],
      [registeredOrigin, 'admin', 'APP_ORIGIN_MISMATCH'],
    ];

    for (const [origin, app, code] of cases) {
      const headers = { Origin: origin };
      if (app) headers['X-AisenHub-App'] = app;
      const response = await routePlatformApi(
        new Request('http://api.local/v1/apps/aisenlens', { headers }),
      );
      const body = await response.json();

      expect(response.status).toBe(403);
      expect(body.error.code).toBe(code);
      expect(response.headers.get('access-control-allow-origin')).toBeNull();
    }
  });

  it('does not add CORS authority when Origin is absent', async () => {
    const response = await routePlatformApi(new Request('http://api.local/v1/apps/aisenlens'));

    expect(response.status).toBe(200);
    expect(response.headers.get('access-control-allow-origin')).toBeNull();
  });
});
