import { describe, expect, it } from 'vitest';

import { AdminAuthClient, AdminAuthError } from './auth';

function storage() {
  const values = new Map<string, string>();
  return {
    values,
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => void values.set(key, value),
    removeItem: (key: string) => void values.delete(key),
  };
}

describe('Admin OAuth authorization boundary', () => {
  it('starts an Admin-specific Authorization Code + PKCE request', async () => {
    const authStorage = storage();
    const client = new AdminAuthClient({
      supabaseUrl: 'http://127.0.0.1:54321',
      clientId: 'admin-local-web',
      redirectUri: 'http://localhost:5174/',
      storage: authStorage,
    });

    const authorization = await client.startAuthorization();
    const url = new URL(authorization.authorizationUrl);
    expect(url.searchParams.get('client_id')).toBe('admin-local-web');
    expect(url.searchParams.get('redirect_uri')).toBe('http://localhost:5174/');
    expect(url.searchParams.get('code_challenge_method')).toBe('S256');
    expect(authStorage.values.has(`aisenhub.admin.oauth.${authorization.state}`)).toBe(true);
  });

  it('exchanges a validated callback and keeps the Admin bearer session origin-local', async () => {
    const authStorage = storage();
    const client = new AdminAuthClient({
      supabaseUrl: 'http://127.0.0.1:54321',
      clientId: 'admin-local-web',
      redirectUri: 'http://localhost:5174/',
      storage: authStorage,
      fetchImplementation: async () =>
        new Response(
          JSON.stringify({
            access_token: 'admin-access-token',
            refresh_token: 'admin-refresh-token',
          }),
          { status: 200 },
        ),
    });

    const authorization = await client.startAuthorization();
    await expect(
      client.completeAuthorization(
        `http://localhost:5174/?code=authorization-code&state=${authorization.state}`,
      ),
    ).resolves.toEqual({
      accessToken: 'admin-access-token',
      refreshToken: 'admin-refresh-token',
    });
    expect(client.accessToken).toBe('admin-access-token');
    expect(authStorage.getItem('aisenhub.access_token')).toBe('admin-access-token');
    expect(authStorage.getItem('aisenhub.refresh_token')).toBe('admin-refresh-token');
    await expect(
      client.completeAuthorization(
        `http://localhost:5174/?code=replayed&state=${authorization.state}`,
      ),
    ).rejects.toBeInstanceOf(AdminAuthError);
  });
});
