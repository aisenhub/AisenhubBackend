import {
  createAdminClient,
  createAdminDataProvider,
  createBusinessCommandClient,
} from '@aisenhub/admin-client';

import { createAdminAccessControlProvider } from './access-control-provider';
import { createAdminAuthProvider } from './auth-provider';
import { createRefineDataProvider } from './refine-data-provider';
import { createAdminSessionStore } from './session-store';
import { AdminAuthClient } from '../auth';

const apiOrigin = import.meta.env.VITE_PLATFORM_ADMIN_API_ORIGIN ?? '/functions/v1/platform-admin';
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL ?? 'http://127.0.0.1:54321';
const adminOAuthClientId = import.meta.env.VITE_ADMIN_OAUTH_CLIENT_ID ?? 'admin-local-web';
const redirectUri =
  typeof window === 'undefined' ? 'http://localhost:5174/' : `${window.location.origin}/`;

const sessionStore = createAdminSessionStore();
const auth = new AdminAuthClient({
  supabaseUrl,
  clientId: adminOAuthClientId,
  redirectUri,
});
const accessToken = () => auth.accessToken;
const adminClient = createAdminClient({
  baseUrl: apiOrigin,
  accessToken,
});
const adminDataProvider = createAdminDataProvider(adminClient);

export const adminRuntime = {
  auth,
  session: sessionStore,
  client: adminClient,
  dataProvider: adminDataProvider,
  refineDataProvider: createRefineDataProvider(adminDataProvider, apiOrigin),
  commands: createBusinessCommandClient(adminClient),
  authProvider: createAdminAuthProvider({
    client: adminClient,
    authClient: auth,
    sessionStore,
  }),
  accessControlProvider: createAdminAccessControlProvider({
    getSession: sessionStore.getSession,
  }),
};
