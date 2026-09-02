import { expect, test } from '@playwright/test';

const adminPageOrigin = process.env.PLAYWRIGHT_ADMIN_BASE_URL ?? 'http://localhost:5174';
const orderId = 'a1000000-0000-4000-8000-000000000001';
const itemId = 'a2000000-0000-4000-8000-000000000001';
const paymentId = 'a3000000-0000-4000-8000-000000000001';
type CommerceRole = 'owner' | 'support';

const order = {
  id: orderId,
  orderNo: 'AH-E2E-ORDER-001',
  userId: 'a4000000-0000-4000-8000-000000000001',
  customerRef: 'a5000000-0000-4000-8000-000000000001',
  status: 'pending',
  currency: 'USD',
  amountTotal: 2500,
  channel: 'local',
  itemCount: 1,
  createdAt: '2026-09-02T01:00:00.000Z',
  paidAt: null,
  fulfilledAt: null,
  cancelledAt: null,
  refundedAt: null,
};

const overview = {
  order,
  items: [
    {
      id: itemId,
      productSku: 'AISENLENS_LIFETIME',
      productName: 'AisenLens Lifetime',
      productVersion: 1,
      quantity: 1,
      unitAmount: 2500,
      totalAmount: 2500,
      salesTerms: {},
      fulfillmentStatus: 'pending',
      refundedAmount: 0,
      grantId: null,
      grantStatus: null,
    },
  ],
  payments: [
    {
      id: paymentId,
      provider: 'local',
      status: 'pending',
      currency: 'USD',
      amount: 2500,
      failureCode: null,
      paidAt: null,
      refundedAt: null,
      disputedAt: null,
      failedAt: null,
    },
  ],
  events: [],
  refunds: [],
  exceptions: [],
  auditTimeline: [],
};

async function mockAdminSession(
  page: import('@playwright/test').Page,
  role: CommerceRole,
): Promise<void> {
  await page.route('**/functions/v1/platform-api/v1/session**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: {
          authenticated: true,
          identity: {
            userId: `a6000000-0000-4000-8000-00000000000${role === 'owner' ? '1' : '2'}`,
            displayName: `${role} operator`,
            avatarUrl: null,
            locale: 'en-US',
            status: 'active',
          },
          expiresAt: '2026-10-01T00:00:00.000Z',
          csrfToken: 'e2e-csrf-token',
        },
        requestId: 'a7000000-0000-4000-8000-000000000001',
      }),
    });
  });
  await page.route('**/functions/v1/platform-admin/v1/admin/session**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: {
          authenticated: true,
          identity: {
            userId: `a6000000-0000-4000-8000-00000000000${role === 'owner' ? '1' : '2'}`,
            displayName: `${role} operator`,
          },
          role,
          aal: 'aal1',
          mfaState: 'required',
          expiresAt: '2026-10-01T00:00:00.000Z',
        },
        requestId: 'a7000000-0000-4000-8000-000000000002',
      }),
    });
  });
}

async function mockCommerceApi(page: import('@playwright/test').Page): Promise<void> {
  await page.route('**/functions/v1/platform-admin/v1/admin/orders**', async (route) => {
    const url = new URL(route.request().url());
    const body = url.pathname.endsWith(`/orders/${orderId}/overview`)
      ? { data: overview, requestId: 'a7000000-0000-4000-8000-000000000004' }
      : {
          data: { items: [order], page: { hasMore: false, nextCursor: null } },
          requestId: 'a7000000-0000-4000-8000-000000000003',
        };
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      headers: { 'x-request-id': body.requestId },
      body: JSON.stringify(body),
    });
  });
}

test.describe('P5 Commerce Admin UI', () => {
  test('opens Order 360 from the server-projected Orders list and exposes MFA guard', async ({
    page,
  }) => {
    await mockAdminSession(page, 'owner');
    await mockCommerceApi(page);
    await page.goto(`${adminPageOrigin}/orders`);

    await expect(page.getByRole('heading', { name: 'Commerce' }).last()).toBeVisible();
    await expect(page.getByRole('link', { name: 'AH-E2E-ORDER-001' })).toBeVisible();
    await page.getByRole('link', { name: 'Open Order 360' }).click();

    await expect(page.getByRole('heading', { name: 'AH-E2E-ORDER-001' })).toBeVisible();
    await expect(page.getByText('Payments', { exact: true })).toBeVisible();
    await expect(page.getByText('Order items', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Verify payment' }).click();
    await page.getByRole('button', { name: 'Review command' }).click();
    await expect(page.getByText('MFA required', { exact: true })).toBeVisible();
    await expect(
      page.getByRole('dialog').getByRole('button', { name: 'Verify payment', exact: true }),
    ).toBeDisabled();
  });

  test('does not expose refund actions to Support while retaining the exceptions surface', async ({
    page,
  }) => {
    await mockAdminSession(page, 'support');
    await mockCommerceApi(page);
    await page.goto(`${adminPageOrigin}/orders/${orderId}`);

    await expect(page.getByRole('heading', { name: 'AH-E2E-ORDER-001' })).toBeVisible();
    await expect(page.getByText('Exceptions', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Refund item' })).toHaveCount(0);
    await expect(
      page.getByText('Support can inspect commerce records but cannot refund an order item.'),
    ).toBeVisible();
  });
});
