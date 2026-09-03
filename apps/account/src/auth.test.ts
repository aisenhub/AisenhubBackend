import { describe, expect, it, vi } from 'vitest';

import { AccountAuthClient, AccountAuthError } from './auth';

const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });

function storage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
    removeItem: (key: string) => values.delete(key),
  };
}

describe('Account OAuth authorization boundary', () => {
  it('starts Authorization Code + PKCE without collecting a password', async () => {
    const client = new AccountAuthClient({
      supabaseUrl: 'http://127.0.0.1:54321/',
      clientId: 'account-local-web',
      redirectUri: 'http://localhost:5173/',
      storage: storage(),
    });

    const authorization = await client.startAuthorization();
    const url = new URL(authorization.authorizationUrl);
    expect(url.pathname).toBe('/auth/v1/authorize');
    expect(url.searchParams.get('client_id')).toBe('account-local-web');
    expect(url.searchParams.get('code_challenge_method')).toBe('S256');
    expect(url.searchParams.get('code_challenge')).toBeTruthy();
    expect(url.searchParams.get('state')).toBe(authorization.state);
  });

  it('exchanges the callback code and keeps only the bearer session in session storage', async () => {
    const authStorage = storage();
    const fetchImplementation = vi.fn(async () =>
      response({
        access_token: 'oauth-access-token',
        refresh_token: 'oauth-refresh-token',
        expires_in: 3600,
      }),
    );
    const client = new AccountAuthClient({
      supabaseUrl: 'http://127.0.0.1:54321',
      clientId: 'account-local-web',
      redirectUri: 'http://localhost:5173/',
      storage: authStorage,
      fetchImplementation,
    });
    const authorization = await client.startAuthorization();

    await expect(
      client.completeAuthorization(
        `http://localhost:5173/?code=authorization-code&state=${authorization.state}`,
      ),
    ).resolves.toEqual({ accessToken: 'oauth-access-token', refreshToken: 'oauth-refresh-token' });
    expect(fetchImplementation).toHaveBeenCalledWith(
      'http://127.0.0.1:54321/auth/v1/token',
      expect.objectContaining({ method: 'POST' }),
    );
    expect(authStorage.getItem('aisenhub.access_token')).toBe('oauth-access-token');
    expect(authStorage.getItem('aisenhub.refresh_token')).toBe('oauth-refresh-token');
  });

  it('maps token exchange failures to safe user-facing errors', async () => {
    const client = new AccountAuthClient({
      supabaseUrl: 'http://127.0.0.1:54321',
      clientId: 'account-local-web',
      redirectUri: 'http://localhost:5173/',
      storage: storage(),
      fetchImplementation: async () => response({ error: 'internal detail' }, 400),
    });
    const authorization = await client.startAuthorization();

    await expect(
      client.completeAuthorization(
        `http://localhost:5173/?code=authorization-code&state=${authorization.state}`,
      ),
    ).rejects.toBeInstanceOf(AccountAuthError);
  });
});
