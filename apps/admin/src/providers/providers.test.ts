import { describe, expect, it } from 'vitest';

import { createAdminClient } from '@aisenhub/admin-client';

import { createAdminAccessControlProvider } from './access-control-provider';
import { createAdminAuthProvider } from './auth-provider';
import { createAdminSessionStore } from './session-store';
import { AdminAuthClient } from '../auth';

const requestId = '00000000-0000-4000-8000-000000000020';
const userId = '00000000-0000-4000-8000-000000000021';
const expiresAt = '2026-09-02T00:00:00.000Z';

function createSessionClient(mfaState: 'required' | 'verified' = 'verified') {
  const requests: string[] = [];
  const client = createAdminClient({
    baseUrl: 'https://api.example.test',
    fetch: async (input, init) => {
      const url = String(input);
      requests.push(`${init?.method ?? 'GET'} ${url}`);
      return new Response(
        JSON.stringify({
          data: {
            authenticated: true,
            identity: { userId, displayName: 'Local Admin' },
            role: 'admin',
            aal: mfaState === 'verified' ? 'aal2' : 'aal1',
            mfaState,
            expiresAt,
          },
          requestId,
        }),
        { headers: { 'content-type': 'application/json' }, status: 200 },
      );
    },
  });
  return { client, requests };
}

function createAuthClient() {
  const values = new Map<string, string>();
  return new AdminAuthClient({
    supabaseUrl: 'https://auth.example.test',
    clientId: 'admin-client',
    redirectUri: 'https://admin.example.test/',
    storage: {
      getItem: (key) => values.get(key) ?? null,
      setItem: (key, value) => void values.set(key, value),
      removeItem: (key) => void values.delete(key),
    },
  });
}

describe('Admin Refine providers', () => {
  it('checks the backend Admin context and keeps identity only in memory', async () => {
    const store = createAdminSessionStore();
    const { client, requests } = createSessionClient();
    const redirects: string[] = [];
    const authProvider = createAdminAuthProvider({
      client,
      authClient: createAuthClient(),
      sessionStore: store,
      redirect: (url) => redirects.push(url),
    });

    await expect(authProvider.check?.()).resolves.toEqual({ authenticated: true });
    await expect(authProvider.getIdentity?.()).resolves.toMatchObject({
      userId,
      role: 'admin',
      aal: 'aal2',
      mfaState: 'verified',
    });
    expect(store.getSession()?.role).toBe('admin');
    expect(requests).toEqual([
      'GET https://api.example.test/v1/admin/session',
      'GET https://api.example.test/v1/admin/session',
    ]);
    expect(redirects).toEqual([]);
  });

  it('starts Admin OAuth and handles Admin 403 without storing credentials', async () => {
    const store = createAdminSessionStore();
    const redirects: string[] = [];
    const { client } = createSessionClient();
    const authProvider = createAdminAuthProvider({
      client,
      authClient: createAuthClient(),
      sessionStore: store,
      redirect: (url) => redirects.push(url),
    });

    await expect(authProvider.login?.({})).resolves.toMatchObject({ success: true });
    expect(redirects[0]).toContain('https://auth.example.test/auth/v1/oauth/authorize?');
    expect(new URL(redirects[0]).searchParams.get('client_id')).toBe('admin-client');

    const deniedClient = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async () =>
        new Response(
          JSON.stringify({
            error: { code: 'ADMIN_ACCESS_DENIED', message: 'Admin access is denied.', requestId },
          }),
          { status: 403 },
        ),
    });
    const deniedAuth = createAdminAuthProvider({
      client: deniedClient,
      authClient: createAuthClient(),
      sessionStore: store,
      redirect: (url) => redirects.push(url),
    });
    await expect(deniedAuth.check?.()).resolves.toMatchObject({
      authenticated: false,
      redirectTo: '/forbidden',
    });
    expect(store.getSession()).toBeNull();
  });

  it('adapts the fixed matrix for Refine actions and denies unknown/MFA actions', async () => {
    const store = createAdminSessionStore();
    const { client } = createSessionClient('required');
    const authProvider = createAdminAuthProvider({
      client,
      authClient: createAuthClient(),
      sessionStore: store,
      redirect: () => undefined,
    });
    await authProvider.check?.();

    const access = createAdminAccessControlProvider({ getSession: store.getSession });
    await expect(access.can({ resource: 'products', action: 'create' })).resolves.toEqual({
      can: false,
      reason: 'mfa_required',
    });
    await expect(access.can({ resource: 'products', action: 'unknown' })).resolves.toEqual({
      can: false,
      reason: 'Unknown Admin resource or action.',
    });
    await expect(
      access.can({ resource: 'productVersions', action: 'product_versions.publish' }),
    ).resolves.toEqual({ can: false, reason: 'mfa_required' });
  });
});
