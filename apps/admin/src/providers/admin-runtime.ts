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
const platformApiOrigin = import.meta.env.VITE_PLATFORM_API_ORIGIN ?? '/functions/v1/platform-api';
const accountOrigin = import.meta.env.VITE_ACCOUNT_ORIGIN ?? 'http://localhost:5173';

const sessionStore = createAdminSessionStore();
const adminClient = createAdminClient({
  baseUrl: apiOrigin,
  app: 'admin',
  csrfToken: sessionStore.getCsrfToken,
});
const platformClient = createAdminClient({
  baseUrl: platformApiOrigin,
  app: 'admin',
  csrfToken: sessionStore.getCsrfToken,
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
    platformClient,
    accountOrigin,
    sessionStore,
  }),
  accessControlProvider: createAdminAccessControlProvider({
    getSession: sessionStore.getSession,
  }),
};
