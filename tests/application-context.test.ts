import { describe, expect, it, vi } from 'vitest';

import {
  createApplicationContextKernel,
  type ApplicationContextRow,
} from '../supabase/functions/_shared/auth/application-context';

const userId = '00000000-0000-4000-8000-000000000001';
const appId = '00000000-0000-4000-8000-000000000101';
const membershipId = '00000000-0000-4000-8000-000000000201';

const token = {
  userId,
  issuer: 'https://local.supabase/auth/v1',
  audience: 'authenticated',
  expiresAt: 1_900_000_000,
  issuedAt: null,
  clientId: 'account-local-web',
  role: 'authenticated',
  aal: 'aal1',
};

function row(overrides: Partial<ApplicationContextRow> = {}): ApplicationContextRow {
  return {
    user_id: userId,
    profile_status: 'active',
    client_id: 'account-local-web',
    client_status: 'active',
    application_id: appId,
    application_slug: 'account',
    application_status: 'active',
    membership_id: membershipId,
    membership_status: 'active',
    membership_policy: 'explicit',
    ...overrides,
  };
}

function request(headers: Record<string, string> = {}) {
  return new Request('https://api.local/v1/app/me', {
    headers: { authorization: 'Bearer access-token', ...headers },
  });
}

function kernel(context: unknown = row(), resolveOrigin = vi.fn(async () => 'account')) {
  return createApplicationContextKernel({
    verifyAccessToken: vi.fn(async () => token),
    resolveContext: vi.fn(async () => context),
    resolveOrigin,
  });
}

describe('application context kernel', () => {
  it('derives the application from the verified client id and ignores app headers', async () => {
    const resolveContext = vi.fn(async () => row());
    const instance = createApplicationContextKernel({
      verifyAccessToken: vi.fn(async () => token),
      resolveContext,
      resolveOrigin: vi.fn(async () => 'account'),
    });

    const context = await instance.authenticate(
      request({ origin: 'https://account.local', 'x-aisenhub-app': 'other-app' }),
      'request-1',
    );

    expect(context.applicationSlug).toBe('account');
    expect(resolveContext).toHaveBeenCalledWith(userId, 'account-local-web');
  });

  it('denies a missing or non-bearer token', async () => {
    const instance = kernel();
    await expect(
      instance.authenticate(new Request('https://api.local/v1/app/me'), 'request-2'),
    ).rejects.toMatchObject({ code: 'AUTHENTICATION_REQUIRED', status: 401 });
    await expect(
      instance.authenticate(
        new Request('https://api.local/v1/app/me', { headers: { authorization: 'Basic secret' } }),
        'request-3',
      ),
    ).rejects.toMatchObject({ code: 'AUTHENTICATION_REQUIRED', status: 401 });
  });

  it.each([
    ['disabled profile', { profile_status: 'disabled' }, 'ACCOUNT_DISABLED'],
    ['disabled client', { client_status: 'disabled' }, 'OAUTH_CLIENT_DISABLED'],
    ['disabled app', { application_status: 'suspended' }, 'APPLICATION_DISABLED'],
    ['missing membership', { membership_id: null, membership_status: null }, 'MEMBERSHIP_REQUIRED'],
    ['pending membership', { membership_status: 'pending' }, 'MEMBERSHIP_REQUIRED'],
    ['suspended membership', { membership_status: 'suspended' }, 'MEMBERSHIP_SUSPENDED'],
  ])('fails closed for %s', async (_label, overrides, code) => {
    await expect(kernel(row(overrides)).authenticate(request(), 'request-4')).rejects.toMatchObject(
      {
        code,
        status: 403,
      },
    );
  });

  it('denies a valid token from a different browser Origin', async () => {
    const resolveOrigin = vi.fn(async () => 'other-app');
    await expect(
      kernel(row(), resolveOrigin).authenticate(
        request({ origin: 'https://other.local' }),
        'request-5',
      ),
    ).rejects.toMatchObject({ code: 'ORIGIN_NOT_ALLOWED', status: 403 });
  });

  it('allows native-style requests without Origin', async () => {
    const resolveOrigin = vi.fn(async () => 'other-app');
    const context = await kernel(row(), resolveOrigin).authenticate(request(), 'request-6');
    expect(context.applicationId).toBe(appId);
    expect(resolveOrigin).not.toHaveBeenCalled();
  });

  it('rejects malformed resolver output without exposing internals', async () => {
    await expect(kernel({}).authenticate(request(), 'request-7')).rejects.toMatchObject({
      code: 'INTERNAL_ERROR',
      status: 502,
    });
  });
});
