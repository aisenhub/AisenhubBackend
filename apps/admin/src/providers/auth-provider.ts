import type { AuthProvider } from '@refinedev/core';
import { AdminSessionResponseSchema, type AdminSessionResponse } from '@aisenhub/contracts';

import type { AdminClient, AdminClientError } from '@aisenhub/admin-client';
import type { AdminSessionStore } from './session-store';

type Redirect = (url: string) => void;

export type AdminAuthProviderOptions = {
  client: AdminClient;
  accountOrigin: string;
  sessionStore: AdminSessionStore;
  redirect?: Redirect;
};

function toError(value: unknown): Error {
  return value instanceof Error ? value : new Error('The Admin session request failed.');
}

function isAdminClientError(value: unknown): value is AdminClientError {
  return value instanceof Error && value.name === 'AdminClientError' && 'code' in value;
}

function loginUrl(accountOrigin: string): string {
  const returnTo = typeof window === 'undefined' ? '/' : window.location.href;
  return `${accountOrigin.replace(/\/$/, '')}/?redirectTo=${encodeURIComponent(returnTo)}`;
}

export function createAdminAuthProvider(options: AdminAuthProviderOptions): AuthProvider {
  const redirect = options.redirect ?? ((url) => window.location.assign(url));
  async function readAdminSession(): Promise<AdminSessionResponse> {
    const adminSession = await options.client.request(
      '/v1/admin/session',
      AdminSessionResponseSchema,
    );
    options.sessionStore.setSession(adminSession.data);
    return adminSession.data;
  }

  return {
    async login() {
      const url = loginUrl(options.accountOrigin);
      redirect(url);
      return { success: true, redirectTo: url };
    },
    async check() {
      try {
        await readAdminSession();
        return { authenticated: true };
      } catch (error) {
        const clientError = isAdminClientError(error) ? error : null;
        const requiresLogin =
          clientError?.status === 401 || clientError?.code === 'AUTHENTICATION_REQUIRED';
        if (requiresLogin) {
          options.sessionStore.clear();
          return {
            authenticated: false,
            logout: clientError?.status === 401,
            redirectTo: options.accountOrigin,
            error: toError(error),
          };
        }
        return { authenticated: false, redirectTo: '/forbidden', error: toError(error) };
      }
    },
    async getIdentity() {
      try {
        const session = await readAdminSession();
        return {
          ...session.identity,
          role: session.role,
          aal: session.aal,
          mfaState: session.mfaState,
          expiresAt: session.expiresAt,
        };
      } catch {
        return null;
      }
    },
    async logout() {
      options.sessionStore.clear();
      redirect(options.accountOrigin);
      return { success: true, redirectTo: options.accountOrigin };
    },
    async onError(error) {
      const clientError = isAdminClientError(error) ? error : null;
      if (clientError?.code === 'MFA_REQUIRED') {
        return { error: clientError, redirectTo: '/mfa' };
      }
      if (clientError?.status === 401) {
        options.sessionStore.clear();
        return { error: clientError, logout: true, redirectTo: options.accountOrigin };
      }
      return { error: toError(error) };
    },
  };
}
