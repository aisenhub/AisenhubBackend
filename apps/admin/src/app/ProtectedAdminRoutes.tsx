import { Authenticated, CanAccess } from '@refinedev/core';
import { Navigate, Route, Routes } from 'react-router-dom';
import type { ReactNode } from 'react';

import { LoadingState, PermissionDeniedState } from '@aisenhub/design-system';
import { Result } from 'antd';
import { AdminLayout } from '../layouts/AdminLayout';
import { OverviewPage } from '../modules/overview/OverviewPage';
import { ApplicationsPage } from '../modules/operations/pages/ApplicationsPage';
import { AuditLogsPage } from '../modules/operations/pages/AuditLogsPage';
import { SystemHealthPage } from '../modules/operations/pages/SystemHealthPage';
import { UsersPage } from '../modules/operations/pages/UsersPage';
import { FeedbackPage } from '../modules/operations/pages/FeedbackPage';
import { RedemptionBatchesPage } from '../modules/redemption/pages/RedemptionBatchesPage';
import { RedemptionCodesPage } from '../modules/redemption/pages/RedemptionCodesPage';
import { RedemptionsPage } from '../modules/redemption/pages/RedemptionsPage';
import { adminRuntime } from '../providers/admin-runtime';
import { CatalogPage } from '../modules/catalog/pages/CatalogPage';
import { FeaturesPage } from '../modules/catalog/pages/FeaturesPage';
import { OriginsPage } from '../modules/catalog/pages/OriginsPage';
import { PricesPage } from '../modules/catalog/pages/PricesPage';
import { ProductCreatePage } from '../modules/catalog/pages/ProductCreatePage';
import { ProductOverviewPage } from '../modules/catalog/pages/ProductOverviewPage';
import { ProductVersionsPage } from '../modules/catalog/pages/ProductVersionsPage';
import { ProductsPage } from '../modules/catalog/pages/ProductsPage';
import { UserOverviewPage } from '../modules/operations/pages/UserOverviewPage';
import { OrderOverviewPage } from '../modules/commerce/pages/OrderOverviewPage';
import { OrdersPage } from '../modules/commerce/pages/OrdersPage';

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

function CatalogPermission({
  children,
  action = 'list',
}: {
  children: ReactNode;
  action?: string;
}) {
  return (
    <CanAccess resource="products" action={action} fallback={<PermissionDeniedState />}>
      {children}
    </CanAccess>
  );
}

function RedemptionPermission({ children }: { children: ReactNode }) {
  return adminRuntime.session.getSession()?.role === 'finance' ? (
    <PermissionDeniedState description="Finance members cannot access Redemption operations." />
  ) : (
    children
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
            path="applications"
            element={
              <CanAccess resource="applications" action="list" fallback={<PermissionDeniedState />}>
                <ApplicationsPage />
              </CanAccess>
            }
          />
          <Route path="users" element={<UsersPage />} />
          <Route path="feedback" element={<FeedbackPage />} />
          <Route
            path="orders"
            element={
              <CanAccess resource="orders" action="list" fallback={<PermissionDeniedState />}>
                <OrdersPage />
              </CanAccess>
            }
          />
          <Route
            path="orders/:orderId"
            element={
              <CanAccess resource="orders" action="show" fallback={<PermissionDeniedState />}>
                <OrderOverviewPage />
              </CanAccess>
            }
          />
          <Route path="customers" element={<UsersPage />} />
          <Route path="customers/users/:userId" element={<UserOverviewPage />} />
          <Route
            path="redemptions"
            element={
              <RedemptionPermission>
                <RedemptionBatchesPage />
              </RedemptionPermission>
            }
          />
          <Route
            path="redemption-codes"
            element={
              <RedemptionPermission>
                <RedemptionCodesPage />
              </RedemptionPermission>
            }
          />
          <Route
            path="redemption-receipts"
            element={
              <RedemptionPermission>
                <RedemptionsPage />
              </RedemptionPermission>
            }
          />
          <Route
            path="audit-logs"
            element={
              <CanAccess resource="auditLogs" action="list" fallback={<PermissionDeniedState />}>
                <AuditLogsPage />
              </CanAccess>
            }
          />
          <Route path="system-health" element={<SystemHealthPage />} />
          <Route
            path="catalog"
            element={
              <CanAccess resource="products" action="list" fallback={<PermissionDeniedState />}>
                <CatalogPage />
              </CanAccess>
            }
          />
          <Route
            path="catalog/products"
            element={
              <CatalogPermission>
                <ProductsPage />
              </CatalogPermission>
            }
          />
          <Route
            path="catalog/products/new"
            element={
              <CatalogPermission action="create">
                <ProductCreatePage />
              </CatalogPermission>
            }
          />
          <Route
            path="catalog/products/:productId"
            element={
              <CatalogPermission>
                <ProductOverviewPage />
              </CatalogPermission>
            }
          />
          <Route
            path="catalog/product-versions"
            element={
              <CatalogPermission>
                <ProductVersionsPage />
              </CatalogPermission>
            }
          />
          <Route
            path="catalog/prices"
            element={
              <CatalogPermission>
                <PricesPage />
              </CatalogPermission>
            }
          />
          <Route
            path="catalog/origins"
            element={
              <CatalogPermission>
                <OriginsPage />
              </CatalogPermission>
            }
          />
          <Route
            path="catalog/features"
            element={
              <CatalogPermission>
                <FeaturesPage />
              </CatalogPermission>
            }
          />
          <Route path="growth" element={<ModuleUnavailablePage />} />
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
