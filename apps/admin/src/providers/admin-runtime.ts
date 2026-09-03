import {
  createAdminClient,
  createAdminDataProvider,
  createBusinessCommandClient,
} from '@aisenhub/admin-client';

import { createAdminAccessControlProvider } from './access-control-provider';
import { createAdminAuthProvider } from './auth-provider';
import { createRefineDataProvider } from './refine-data-provider';
import { createAdminSessionStore } from './session-store';

const apiOrigin = import.meta.env.VITE_PLATFORM_ADMIN_API_ORIGIN ?? '/functions/v1/platform-admin';
const accountOrigin = import.meta.env.VITE_ACCOUNT_ORIGIN ?? 'http://localhost:5173';

const sessionStore = createAdminSessionStore();
const accessToken = () => globalThis.sessionStorage?.getItem('aisenhub.access_token');
const adminClient = createAdminClient({
  baseUrl: apiOrigin,
  accessToken,
});
const adminDataProvider = createAdminDataProvider(adminClient);

export const adminRuntime = {
  session: sessionStore,
  client: adminClient,
  dataProvider: adminDataProvider,
  refineDataProvider: createRefineDataProvider(adminDataProvider, apiOrigin),
  commands: createBusinessCommandClient(adminClient),
  authProvider: createAdminAuthProvider({
    client: adminClient,
    accountOrigin,
    sessionStore,
  }),
  accessControlProvider: createAdminAccessControlProvider({
    getSession: sessionStore.getSession,
  }),
};
