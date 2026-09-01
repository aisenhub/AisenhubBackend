import { describe, expect, it } from 'vitest';

import { createAdminClient } from '@aisenhub/admin-client';

import { createAdminAccessControlProvider } from './access-control-provider';
import { createAdminAuthProvider } from './auth-provider';
import { createAdminSessionStore } from './session-store';

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
      if (url.endsWith('/v1/session')) {
        return new Response(
          JSON.stringify({
            data: {
              authenticated: true,
              identity: {
                userId,
                displayName: 'Local Admin',
                avatarUrl: null,
                locale: 'zh-CN',
                status: 'active',
              },
              expiresAt,
              csrfToken: 'csrf-memory-only',
            },
            requestId,
          }),
          { headers: { 'content-type': 'application/json' }, status: 200 },
        );
      }
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

describe('Admin Refine providers', () => {
  it('checks the backend Admin Session and keeps identity/CSRF only in memory', async () => {
    const store = createAdminSessionStore();
    const { client, requests } = createSessionClient();
    const redirects: string[] = [];
    const authProvider = createAdminAuthProvider({
      client,
      accountOrigin: 'https://account.example.test',
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
    expect(store.getCsrfToken()).toBe('csrf-memory-only');
    expect(store.getSession()?.role).toBe('admin');
    expect(requests).toEqual([
      'GET https://api.example.test/v1/session',
      'GET https://api.example.test/v1/admin/session',
      'GET https://api.example.test/v1/session',
      'GET https://api.example.test/v1/admin/session',
    ]);
    expect(redirects).toEqual([]);
  });

  it('redirects login to Account and handles Admin 403 without storing credentials', async () => {
    const store = createAdminSessionStore();
    const redirects: string[] = [];
    const { client } = createSessionClient();
    const authProvider = createAdminAuthProvider({
      client,
      accountOrigin: 'https://account.example.test',
      sessionStore: store,
      redirect: (url) => redirects.push(url),
    });

    await expect(authProvider.login?.({})).resolves.toMatchObject({ success: true });
    expect(redirects[0]).toContain('https://account.example.test/?redirectTo=');

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
      accountOrigin: 'https://account.example.test',
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
      accountOrigin: 'https://account.example.test',
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
