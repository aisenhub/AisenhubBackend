import { Refine } from '@refinedev/core';
import { BrowserRouter } from 'react-router-dom';

import { ErrorBoundary } from './ErrorBoundary';
import { AdminLayout } from '../layouts/AdminLayout';
import { OverviewPage } from '../modules/overview/OverviewPage';
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
            options={{ syncWithLocation: true }}
          >
            <AdminLayout>
              <OverviewPage />
            </AdminLayout>
          </Refine>
        </BrowserRouter>
      </AdminProviders>
    </ErrorBoundary>
  );
}
