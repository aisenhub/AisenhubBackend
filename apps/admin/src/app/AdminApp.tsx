import { Refine } from '@refinedev/core';
import { useNotificationProvider } from '@refinedev/antd';
import { BrowserRouter } from 'react-router-dom';

import { ErrorBoundary } from './ErrorBoundary';
import { ProtectedAdminRoutes } from './ProtectedAdminRoutes';
import { adminRuntime } from '../providers/admin-runtime';
import { AdminProviders } from '../providers/AdminProviders';
import { adminResources } from './module-registry';
import { adminRouterProvider } from './router-provider';
import { AdminAuthError } from '../auth';
import { LoadingState } from '@aisenhub/design-system';
import { useEffect, useState, type ReactNode } from 'react';

function AdminAuthBootstrap({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const callbackUrl = new URL(window.location.href);
    const hasAuthorizationCallback =
      callbackUrl.searchParams.has('code') && callbackUrl.searchParams.has('state');
    const authorization = hasAuthorizationCallback
      ? adminRuntime.auth.completeAuthorization(callbackUrl).then(() => {
          window.history.replaceState(
            {},
            document.title,
            callbackUrl.origin + callbackUrl.pathname,
          );
        })
      : Promise.resolve();

    authorization
      .catch((value: unknown) => {
        adminRuntime.auth.signOut();
        if (active) {
          setError(value instanceof AdminAuthError ? value.message : 'Admin sign-in failed.');
        }
      })
      .finally(() => {
        if (active) setReady(true);
      });

    return () => {
      active = false;
    };
  }, []);

  if (!ready) return <LoadingState description="Preparing secure Admin sign-in…" />;
  if (error) return <LoadingState description={error} />;
  return children;
}

export function AdminApp() {
  return (
    <ErrorBoundary>
      <AdminProviders>
        <AdminAuthBootstrap>
          <BrowserRouter>
            <Refine
              resources={adminResources}
              routerProvider={adminRouterProvider}
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
        </AdminAuthBootstrap>
      </AdminProviders>
    </ErrorBoundary>
  );
}
