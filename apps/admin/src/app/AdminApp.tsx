import { Refine } from '@refinedev/core';
import { useNotificationProvider } from '@refinedev/antd';
import { BrowserRouter } from 'react-router-dom';

import { ErrorBoundary } from './ErrorBoundary';
import { ProtectedAdminRoutes } from './ProtectedAdminRoutes';
import { adminRuntime } from '../providers/admin-runtime';
import { AdminProviders } from '../providers/AdminProviders';

export function AdminApp() {
  return (
    <ErrorBoundary>
      <AdminProviders>
        <BrowserRouter>
          <Refine
            authProvider={adminRuntime.authProvider}
            accessControlProvider={adminRuntime.accessControlProvider}
            dataProvider={adminRuntime.refineDataProvider}
            notificationProvider={useNotificationProvider}
            options={{
              syncWithLocation: true,
              warnWhenUnsavedChanges: false,
            }}
          >
            <ProtectedAdminRoutes />
          </Refine>
        </BrowserRouter>
      </AdminProviders>
    </ErrorBoundary>
  );
}
