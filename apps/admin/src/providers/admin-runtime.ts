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
const adminClient = createAdminClient({
  baseUrl: apiOrigin,
  csrfToken: sessionStore.getCsrfToken,
});
const adminDataProvider = createAdminDataProvider(adminClient);

export const adminRuntime = {
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
