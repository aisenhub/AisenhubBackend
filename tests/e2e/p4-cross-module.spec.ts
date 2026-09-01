import { expect, test } from '@playwright/test';

const accountPageOrigin = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:5173';
const adminPageOrigin = 'http://localhost:5174';
const aisenLensOrigin = 'http://localhost:5175';
const productId = '23000000-0000-4000-8000-000000000001';
const productVersionId = '24000000-0000-4000-8000-000000000001';
const normalUserId = '10000000-0000-4000-8000-000000000005';

const roles = {
  owner: { email: 'owner.local@aisenhub.test', password: 'LocalOnly-Owner-2026!' },
  support: { email: 'support.local@aisenhub.test', password: 'LocalOnly-Support-2026!' },
  finance: { email: 'finance.local@aisenhub.test', password: 'LocalOnly-Finance-2026!' },
} as const;

type RequestInit = {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
};

type ApiResult = {
  status: number;
  body: {
    data?: Record<string, unknown>;
    error?: { code?: string; requestId?: string };
    requestId?: string;
  };
  requestId: string | null;
};

async function signInToAdmin(
  page: import('@playwright/test').Page,
  role: (typeof roles)[keyof typeof roles],
): Promise<void> {
  await page.goto(accountPageOrigin);
  await expect(page.getByRole('heading', { name: 'One account for your tools.' })).toBeVisible();
  await page.getByLabel('Email address').fill(role.email);
  await page.getByLabel('Password').fill(role.password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('heading', { name: /Welcome back/ })).toBeVisible();
  await page.goto(`${adminPageOrigin}/overview`);
  await expect(page.getByText('Operations workspace', { exact: true })).toBeVisible();
}

async function apiFetch(
  page: import('@playwright/test').Page,
  path: string,
  init?: RequestInit,
): Promise<ApiResult> {
  return page.evaluate(
    async ({ path, init }) => {
      const response = await fetch(path, init);
      const body = (await response.json()) as ApiResult['body'];
      return {
        status: response.status,
        body,
        requestId: response.headers.get('x-request-id'),
      };
    },
    { path, init },
  );
}

async function adminCsrf(page: import('@playwright/test').Page): Promise<string> {
  const session = await apiFetch(page, '/functions/v1/platform-api/v1/session', {
    headers: { 'X-AisenHub-App': 'admin' },
  });
  expect(session.status).toBe(200);
  const csrfToken = session.body.data?.csrfToken;
  expect(typeof csrfToken).toBe('string');
  return csrfToken as string;
}

async function protectedCommand(
  page: import('@playwright/test').Page,
  path: string,
  csrfToken: string,
  body: Record<string, unknown>,
): Promise<ApiResult> {
  return apiFetch(page, `/functions/v1/platform-admin${path}`, {
    method: 'POST',
    headers: {
      'X-AisenHub-App': 'admin',
      'X-CSRF-Token': csrfToken,
      'Idempotency-Key': `p4-${crypto.randomUUID()}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      reason: 'P4 browser integration security proof',
      confirmation: true,
      ...body,
    }),
  });
}

test.describe('P4 cross-module Admin and product integration', () => {
  test('projects Catalog, Redemption, Customer, Audit, and product access without leaking private data', async ({
    page,
    request,
  }) => {
    await signInToAdmin(page, roles.owner);

    const products = await apiFetch(page, '/functions/v1/platform-admin/v1/admin/products');
    expect(products.status, JSON.stringify(products.body)).toBe(200);
    expect(products.body.data?.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: productId,
          sku: 'AISENLENS_LIFETIME',
          status: 'active',
          currentVersion: expect.objectContaining({ id: productVersionId, status: 'published' }),
        }),
      ]),
    );

    const overview = await apiFetch(
      page,
      `/functions/v1/platform-admin/v1/admin/products/${productId}/overview`,
    );
    expect(overview.status).toBe(200);
    expect(overview.body.data).toEqual(
      expect.objectContaining({
        product: expect.objectContaining({ id: productId, sku: 'AISENLENS_LIFETIME' }),
        versions: expect.arrayContaining([expect.objectContaining({ id: productVersionId })]),
        prices: expect.arrayContaining([expect.objectContaining({ productVersion: 1 })]),
        redemptionBatches: expect.arrayContaining([
          expect.objectContaining({ productSku: 'AISENLENS_LIFETIME' }),
        ]),
      }),
    );
    expect(JSON.stringify(overview.body)).not.toMatch(/codeHash|plaintext|token|secret/i);

    const batches = await apiFetch(
      page,
      '/functions/v1/platform-admin/v1/admin/redemption-batches',
    );
    expect(batches.status).toBe(200);
    expect(batches.body.data?.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          name: 'Local Active Batch',
          productSku: 'AISENLENS_LIFETIME',
          status: 'active',
        }),
      ]),
    );
    expect(JSON.stringify(batches.body)).not.toMatch(/codeHash|plaintext|token|secret/i);

    const customer = await apiFetch(
      page,
      `/functions/v1/platform-admin/v1/admin/users/${normalUserId}/overview`,
    );
    expect(customer.status).toBe(200);
    expect(customer.body.data).toEqual(
      expect.objectContaining({
        profile: expect.objectContaining({ userId: normalUserId, status: 'active' }),
        entitlements: expect.arrayContaining([
          expect.objectContaining({ productSku: 'AISENLENS_LIFETIME', status: 'active' }),
        ]),
        auditTimeline: expect.arrayContaining([
          expect.objectContaining({ action: 'entitlements.grant' }),
        ]),
      }),
    );
    expect(JSON.stringify(customer.body)).not.toMatch(/sessionToken|csrfHash|tokenHash|password/i);

    await page.goto(`${adminPageOrigin}/customers/users/${normalUserId}`);
    await expect(page.getByText('Audit timeline', { exact: true })).toBeVisible();

    const normalUserContext = await page.context().browser()?.newContext();
    expect(normalUserContext).toBeTruthy();
    const normalUserPage = await normalUserContext!.newPage();
    await normalUserPage.goto(accountPageOrigin);
    await expect(
      normalUserPage.getByRole('heading', { name: 'One account for your tools.' }),
    ).toBeVisible();
    await normalUserPage.getByLabel('Email address').fill('normal-user.local@aisenhub.test');
    await normalUserPage.getByLabel('Password').fill('LocalOnly-NormalUser-2026!');
    await normalUserPage.getByRole('button', { name: 'Sign in' }).click();
    await expect(normalUserPage.getByRole('heading', { name: /Welcome back/ })).toBeVisible();
    const sessionCookie = (await normalUserPage.context().cookies()).find(
      (cookie) => cookie.name === '__Host-aisenhub_session',
    );
    expect(sessionCookie?.value).toBeTruthy();
    const access = await request.get(
      'http://127.0.0.1:54321/functions/v1/platform-api/v1/access/aisenlens.app.access',
      {
        headers: {
          Origin: aisenLensOrigin,
          'X-AisenHub-App': 'aisenlens',
          Cookie: `__Host-aisenhub_session=${sessionCookie?.value}`,
        },
      },
    );
    expect(access.status()).toBe(200);
    expect((await access.json()).data).toMatchObject({
      allowed: true,
      feature: 'aisenlens.app.access',
      sourceProduct: 'AISENLENS_LIFETIME',
      value: true,
    });
    await normalUserContext!.close();
  });

  test('enforces MFA and role boundaries for every high-risk cross-module command', async ({
    browser,
  }) => {
    const ownerContext = await browser.newContext();
    const ownerPage = await ownerContext.newPage();
    await signInToAdmin(ownerPage, roles.owner);
    const csrfToken = await adminCsrf(ownerPage);

    const highRiskCommands = [
      [
        '/v1/admin/products',
        { sku: 'P4_E2E_DRAFT', name: 'P4 E2E Draft', billingType: 'one_time' },
      ],
      [`/v1/admin/product-versions/${productVersionId}/publish`, {}],
      [`/v1/admin/products/${productId}/set-current-version`, { productVersionId }],
      [
        '/v1/admin/redemption-batches',
        {
          name: 'P4 E2E Batch',
          productId,
          productVersionId,
          codePrefix: 'P4-E2E',
          quantity: 1,
          source: 'p4-e2e',
        },
      ],
      [`/v1/admin/users/${normalUserId}/entitlements/grant`, { productVersionId }],
    ] as const;

    for (const [path, body] of highRiskCommands) {
      const response = await protectedCommand(ownerPage, path, csrfToken, body);
      expect(response.status, path).toBe(403);
      expect(response.body.error?.code, path).toBe('MFA_REQUIRED');
      expect(response.requestId, path).toBeTruthy();
    }
    await ownerContext.close();

    for (const [roleName, role] of Object.entries({
      support: roles.support,
      finance: roles.finance,
    })) {
      const context = await browser.newContext();
      const page = await context.newPage();
      await signInToAdmin(page, role);
      const token = await adminCsrf(page);
      const response = await protectedCommand(
        page,
        `/v1/admin/users/${normalUserId}/entitlements/grant`,
        token,
        { productVersionId },
      );
      expect(response.status, roleName).toBe(403);
      expect(response.body.error?.code, roleName).toBe(
        roleName === 'support' ? 'MFA_REQUIRED' : 'ADMIN_ACCESS_DENIED',
      );
      expect(response.requestId, roleName).toBeTruthy();
      await context.close();
    }
  });
});
