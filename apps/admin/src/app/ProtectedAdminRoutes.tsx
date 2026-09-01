import { Authenticated, CanAccess } from '@refinedev/core';
import { Navigate, Route, Routes } from 'react-router-dom';

import { LoadingState, PermissionDeniedState } from '@aisenhub/design-system';
import { Result } from 'antd';
import { AdminLayout } from '../layouts/AdminLayout';
import { OverviewPage } from '../modules/overview/OverviewPage';

function ModuleUnavailablePage() {
  return (
    <Result
      status="info"
      title="Module not available"
      subTitle="This module is not enabled in the current delivery scope. No placeholder data is shown."
    />
  );
}

function NotFoundPage() {
  return (
    <Result
      status="404"
      title="Page not found"
      subTitle="This Admin route is not registered or is no longer available."
    />
  );
}

function ForbiddenPage() {
  return (
    <PermissionDeniedState description="Your Admin membership does not allow access to this area." />
  );
}

function ProtectedContent() {
  return (
    <Authenticated
      key="admin-protected-routes"
      loading={<LoadingState description="Checking Admin session…" />}
    >
      <AdminLayout>
        <Routes>
          <Route index element={<Navigate to="/overview" replace />} />
          <Route path="overview" element={<OverviewPage />} />
          <Route
            path="catalog"
            element={
              <CanAccess resource="products" action="list" fallback={<PermissionDeniedState />}>
                <ModuleUnavailablePage />
              </CanAccess>
            }
          />
          <Route path="growth" element={<ModuleUnavailablePage />} />
          <Route path="customers" element={<ModuleUnavailablePage />} />
          <Route path="platform" element={<ModuleUnavailablePage />} />
          <Route path="*" element={<NotFoundPage />} />
        </Routes>
      </AdminLayout>
    </Authenticated>
  );
}

export function ProtectedAdminRoutes() {
  return (
    <Routes>
      <Route path="/forbidden" element={<ForbiddenPage />} />
      <Route path="*" element={<ProtectedContent />} />
    </Routes>
  );
}
