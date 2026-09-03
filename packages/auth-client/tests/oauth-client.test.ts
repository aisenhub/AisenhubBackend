import { describe, expect, it } from 'vitest';

import { OAuthClient, OAuthClientError, type OAuthStorage } from '../src/index';

function storage(): OAuthStorage {
  const values = new Map<string, string>();
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => void values.set(key, value),
    removeItem: (key) => void values.delete(key),
  };
}

describe('OAuth client', () => {
  it('creates a PKCE authorization request and exchanges a validated callback', async () => {
    const stateStore = storage();
    let tokenRequest: Request | undefined;
    const client = new OAuthClient({
      authorizationEndpoint: 'https://auth.example.test/auth/v1/oauth/authorize',
      tokenEndpoint: 'https://auth.example.test/auth/v1/oauth/token',
      clientId: 'client-a',
      redirectUri: 'https://app.example.test/oauth/callback',
      storage: stateStore,
      fetch: async (input, init) => {
        tokenRequest = new Request(input, init);
        return new Response(
          JSON.stringify({
            access_token: 'access-a',
            refresh_token: 'refresh-a',
            expires_in: 3600,
          }),
          { status: 200 },
        );
      },
    });

    const start = await client.startAuthorization();
    const authorizationUrl = new URL(start.authorizationUrl);
    expect(authorizationUrl.searchParams.get('client_id')).toBe('client-a');
    expect(authorizationUrl.searchParams.get('code_challenge_method')).toBe('S256');
    expect(authorizationUrl.searchParams.get('code_challenge')).not.toBe(start.codeVerifier);

    const tokens = await client.exchangeCode(
      client.readCallback(
        `https://app.example.test/oauth/callback?code=code-a&state=${encodeURIComponent(start.state)}`,
      ),
    );
    expect(tokens.accessToken).toBe('access-a');
    expect(tokenRequest?.headers.get('content-type')).toContain(
      'application/x-www-form-urlencoded',
    );
    expect(await tokenRequest?.text()).toContain('grant_type=authorization_code');
  });

  it('rejects callback state replay and mismatch', async () => {
    const client = new OAuthClient({
      authorizationEndpoint: 'https://auth.example.test/authorize',
      tokenEndpoint: 'https://auth.example.test/token',
      clientId: 'client-a',
      redirectUri: 'https://app.example.test/callback',
      storage: storage(),
    });
    const start = await client.startAuthorization();
    expect(() =>
      client.readCallback(`https://app.example.test/callback?code=code&state=wrong`),
    ).toThrow(OAuthClientError);
    const callback = client.readCallback(
      `https://app.example.test/callback?code=code&state=${start.state}`,
    );
    expect(callback.nonce).toBe(start.nonce);
    expect(() =>
      client.readCallback(`https://app.example.test/callback?code=code&state=${start.state}`),
    ).toThrow(OAuthClientError);
  });

  it('normalizes refresh failures without exposing provider response details', async () => {
    const client = new OAuthClient({
      authorizationEndpoint: 'https://auth.example.test/authorize',
      tokenEndpoint: 'https://auth.example.test/token',
      clientId: 'client-a',
      redirectUri: 'https://app.example.test/callback',
      fetch: async () =>
        new Response(JSON.stringify({ error: 'invalid_grant', secret: 'redacted' }), {
          status: 400,
        }),
    });
    await expect(client.refresh('refresh-a')).rejects.toThrow('The OAuth token exchange failed.');
  });
});
