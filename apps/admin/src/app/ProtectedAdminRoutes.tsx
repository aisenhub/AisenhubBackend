import { Authenticated, CanAccess } from '@refinedev/core';
import { Navigate, Route, Routes } from 'react-router-dom';
import { lazy, Suspense, type ReactNode } from 'react';

import { LoadingState, PermissionDeniedState } from '@aisenhub/design-system';
import { Result } from 'antd';
import { AdminLayout } from '../layouts/AdminLayout';
import { adminRuntime } from '../providers/admin-runtime';

const OverviewPage = lazy(() =>
  import('../modules/overview/OverviewPage').then(({ OverviewPage: page }) => ({ default: page })),
);
const ApplicationsPage = lazy(() =>
  import('../modules/operations/pages/ApplicationsPage').then(({ ApplicationsPage: page }) => ({
    default: page,
  })),
);
const AuditLogsPage = lazy(() =>
  import('../modules/operations/pages/AuditLogsPage').then(({ AuditLogsPage: page }) => ({
    default: page,
  })),
);
const SystemHealthPage = lazy(() =>
  import('../modules/operations/pages/SystemHealthPage').then(({ SystemHealthPage: page }) => ({
    default: page,
  })),
);
const UsersPage = lazy(() =>
  import('../modules/operations/pages/UsersPage').then(({ UsersPage: page }) => ({
    default: page,
  })),
);
const FeedbackPage = lazy(() =>
  import('../modules/operations/pages/FeedbackPage').then(({ FeedbackPage: page }) => ({
    default: page,
  })),
);
const RedemptionBatchesPage = lazy(() =>
  import('../modules/redemption/pages/RedemptionBatchesPage').then(
    ({ RedemptionBatchesPage: page }) => ({
      default: page,
    }),
  ),
);
const RedemptionCodesPage = lazy(() =>
  import('../modules/redemption/pages/RedemptionCodesPage').then(
    ({ RedemptionCodesPage: page }) => ({
      default: page,
    }),
  ),
);
const RedemptionsPage = lazy(() =>
  import('../modules/redemption/pages/RedemptionsPage').then(({ RedemptionsPage: page }) => ({
    default: page,
  })),
);
const CatalogPage = lazy(() =>
  import('../modules/catalog/pages/CatalogPage').then(({ CatalogPage: page }) => ({
    default: page,
  })),
);
const FeaturesPage = lazy(() =>
  import('../modules/catalog/pages/FeaturesPage').then(({ FeaturesPage: page }) => ({
    default: page,
  })),
);
const OriginsPage = lazy(() =>
  import('../modules/catalog/pages/OriginsPage').then(({ OriginsPage: page }) => ({
    default: page,
  })),
);
const PricesPage = lazy(() =>
  import('../modules/catalog/pages/PricesPage').then(({ PricesPage: page }) => ({ default: page })),
);
const ProductCreatePage = lazy(() =>
  import('../modules/catalog/pages/ProductCreatePage').then(({ ProductCreatePage: page }) => ({
    default: page,
  })),
);
const ProductOverviewPage = lazy(() =>
  import('../modules/catalog/pages/ProductOverviewPage').then(({ ProductOverviewPage: page }) => ({
    default: page,
  })),
);
const ProductVersionsPage = lazy(() =>
  import('../modules/catalog/pages/ProductVersionsPage').then(({ ProductVersionsPage: page }) => ({
    default: page,
  })),
);
const ProductsPage = lazy(() =>
  import('../modules/catalog/pages/ProductsPage').then(({ ProductsPage: page }) => ({
    default: page,
  })),
);
const UserOverviewPage = lazy(() =>
  import('../modules/operations/pages/UserOverviewPage').then(({ UserOverviewPage: page }) => ({
    default: page,
  })),
);
const OrderOverviewPage = lazy(() =>
  import('../modules/commerce/pages/OrderOverviewPage').then(({ OrderOverviewPage: page }) => ({
    default: page,
  })),
);
const OrdersPage = lazy(() =>
  import('../modules/commerce/pages/OrdersPage').then(({ OrdersPage: page }) => ({
    default: page,
  })),
);

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
        <Suspense fallback={<LoadingState description="Loading Admin module…" />}>
          <Routes>
            <Route index element={<Navigate to="/overview" replace />} />
            <Route path="overview" element={<OverviewPage />} />
            <Route
              path="applications"
              element={
                <CanAccess
                  resource="applications"
                  action="list"
                  fallback={<PermissionDeniedState />}
                >
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
        </Suspense>
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
