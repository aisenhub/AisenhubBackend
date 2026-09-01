import { describe, expect, it, vi } from 'vitest';

import { AccountAuthClient, AccountAuthError } from './auth';

const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });

describe('Account Auth boundary', () => {
  it('keeps Supabase access tokens in memory and supports the password flow', async () => {
    const fetchImplementation = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      expect(init?.body).toBe(JSON.stringify({ email: 'user@example.test', password: 'secret' }));
      return response({ access_token: 'supabase-access-token' });
    });
    const client = new AccountAuthClient({
      supabaseUrl: 'http://127.0.0.1:54321/',
      anonKey: 'local-anon-key',
      fetchImplementation,
    });

    await expect(client.signInWithPassword('user@example.test', 'secret')).resolves.toEqual({
      accessToken: 'supabase-access-token',
    });
    expect(client.accessToken).toBe('supabase-access-token');
    expect(fetchImplementation).toHaveBeenCalledWith(
      'http://127.0.0.1:54321/auth/v1/token?grant_type=password',
      expect.objectContaining({ method: 'POST' }),
    );
    expect(globalThis.localStorage).toBeUndefined();
  });

  it('supports PKCE code exchange inside the Account boundary', async () => {
    const fetchImplementation = vi.fn(async () => response({ access_token: 'pkce-token' }));
    const client = new AccountAuthClient({
      supabaseUrl: 'http://127.0.0.1:54321',
      anonKey: 'local-anon-key',
      fetchImplementation,
    });

    await client.exchangePkceCode('authorization-code', 'verifier');
    expect(fetchImplementation).toHaveBeenCalledWith(
      'http://127.0.0.1:54321/auth/v1/token?grant_type=pkce',
      expect.objectContaining({
        body: JSON.stringify({ auth_code: 'authorization-code', code_verifier: 'verifier' }),
      }),
    );
  });

  it('maps Auth failures to safe user-facing errors', async () => {
    const client = new AccountAuthClient({
      supabaseUrl: 'http://127.0.0.1:54321',
      anonKey: 'local-anon-key',
      fetchImplementation: async () => response({ error: 'internal detail' }, 400),
    });

    await expect(client.signInWithPassword('user@example.test', 'secret')).rejects.toBeInstanceOf(
      AccountAuthError,
    );
  });
});
