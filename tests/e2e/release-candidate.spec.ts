import { expect, test } from '@playwright/test';

const accountPageOrigin = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:5173';
const adminPageOrigin = process.env.PLAYWRIGHT_ADMIN_BASE_URL ?? 'http://localhost:5174';
const normalUser = {
  email: 'normal-user.local@aisenhub.test',
  password: 'LocalOnly-NormalUser-2026!',
};
const owner = {
  email: 'owner.local@aisenhub.test',
  password: 'LocalOnly-Owner-2026!',
};
const normalUserId = '10000000-0000-4000-8000-000000000005';
const releaseCode = 'AH-LOCAL-ACTIVE-AAAA-BBBB-CCCC-DDDD-EEEE-FF';

type ApiBody = {
  data?: Record<string, unknown>;
  error?: { code?: string };
  requestId?: string;
};

type ApiResult = {
  status: number;
  body: ApiBody;
  requestId: string | null;
};

async function signIn(
  page: import('@playwright/test').Page,
  credentials: typeof normalUser,
): Promise<void> {
  await page.goto(accountPageOrigin);
  await expect(page.getByRole('heading', { name: 'One account for your tools.' })).toBeVisible();
  await page.getByLabel('Email address').fill(credentials.email);
  await page.getByLabel('Password').fill(credentials.password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('heading', { name: /Welcome back/ })).toBeVisible();
}

async function apiFetch(
  page: import('@playwright/test').Page,
  path: string,
  init?: { method?: string; headers?: Record<string, string>; body?: string },
): Promise<ApiResult> {
  return page.evaluate(
    async ({ path, init }) => {
      const response = await fetch(path, init);
      return {
        status: response.status,
        body: (await response.json()) as ApiBody,
        requestId: response.headers.get('x-request-id'),
      };
    },
    { path, init },
  );
}

test.describe('RELEASE-CANDIDATE platform journey', () => {
  test('completes account, catalog, redemption, feedback, deletion, and audit trace', async ({
    browser,
  }) => {
    const userContext = await browser.newContext();
    const userPage = await userContext.newPage();
    const traceIds: string[] = [];

    try {
      await signIn(userPage, normalUser);

      const catalog = await apiFetch(userPage, '/functions/v1/platform-public/v1/products/public');
      expect(catalog.status).toBe(200);
      expect(catalog.body.data?.products).toEqual([
        expect.objectContaining({ sku: 'AISENLENS_LIFETIME', version: 1 }),
      ]);
      expect(JSON.stringify(catalog.body)).not.toMatch(/price|hash|grant|audit/i);
      expect(catalog.requestId).toBeTruthy();
      traceIds.push(catalog.requestId as string);

      const entitlementsBefore = await apiFetch(
        userPage,
        '/functions/v1/platform-api/v1/me/entitlements',
        { headers: { 'X-AisenHub-App': 'account' } },
      );
      expect(entitlementsBefore.status).toBe(200);
      expect(entitlementsBefore.body.data?.entitlements).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ feature: 'aisenlens.app.access', value: true }),
        ]),
      );

      const redemptionResponse = userPage.waitForResponse((response) =>
        response.url().includes('/functions/v1/platform-api/v1/redemptions'),
      );
      await userPage.getByLabel('Redemption code').fill(releaseCode);
      await userPage.getByRole('button', { name: 'Redeem' }).click();
      const redemption = await redemptionResponse;
      const redemptionBody = (await redemption.json()) as ApiBody;
      expect(redemption.status(), JSON.stringify(redemptionBody)).toBe(200);
      expect(redemptionBody.data).toEqual(expect.objectContaining({ status: 'redeemed' }));
      expect(JSON.stringify(redemptionBody)).not.toMatch(/plaintext|secret|token|hash/i);
      expect(redemption.headers()['x-request-id']).toBeTruthy();
      traceIds.push(redemption.headers()['x-request-id'] as string);
      await expect(
        userPage.getByText('Redemption completed. Your platform access is now updated.'),
      ).toBeVisible();

      const session = await apiFetch(userPage, '/functions/v1/platform-api/v1/session', {
        headers: { 'X-AisenHub-App': 'account' },
      });
      expect(session.status).toBe(200);
      expect(session.body.data?.authenticated).toBe(true);
      expect(session.requestId).toBeTruthy();
      traceIds.push(session.requestId as string);
      const csrfToken = session.body.data?.csrfToken;
      expect(typeof csrfToken).toBe('string');

      const feedback = await apiFetch(userPage, '/functions/v1/platform-api/v1/feedback', {
        method: 'POST',
        headers: {
          'X-AisenHub-App': 'account',
          'X-CSRF-Token': csrfToken as string,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          kind: 'release-candidate',
          title: 'Release candidate journey feedback',
          content: 'The Local release candidate journey completed successfully.',
        }),
      });
      expect(feedback.status).toBe(201);
      expect(feedback.body.data).toEqual(expect.objectContaining({ status: 'open' }));
      expect(feedback.requestId).toBeTruthy();
      traceIds.push(feedback.requestId as string);

      const deletionResponse = userPage.waitForResponse((response) =>
        response.url().includes('/functions/v1/platform-api/v1/me/deletion-requests'),
      );
      await userPage.getByLabel('Confirm password').fill(normalUser.password);
      await userPage
        .getByLabel('I understand this will sign me out and schedule account deletion.')
        .check();
      await userPage.getByRole('button', { name: 'Request account deletion' }).click();
      const deletion = await deletionResponse;
      expect(deletion.status()).toBe(202);
      const deletionBody = (await deletion.json()) as ApiBody;
      expect(deletionBody.data).toEqual(
        expect.objectContaining({ status: 'pending', deletionRequestId: expect.any(String) }),
      );
      expect(JSON.stringify(deletionBody)).not.toMatch(/password|token|secret|hash/i);
      expect(deletion.headers()['x-request-id']).toBeTruthy();
      traceIds.push(deletion.headers()['x-request-id'] as string);
      await expect(
        userPage.getByText('Your account deletion request was submitted.'),
      ).toBeVisible();
      await expect(
        userPage.getByRole('heading', { name: 'One account for your tools.' }),
      ).toBeVisible();
    } finally {
      await userContext.close();
    }

    expect(new Set(traceIds).size).toBe(traceIds.length);

    const adminContext = await browser.newContext();
    const adminPage = await adminContext.newPage();
    try {
      await signIn(adminPage, owner);
      await adminPage.goto(`${adminPageOrigin}/customers/users/${normalUserId}`);
      await expect(
        adminPage.getByText(`User 360 · ${normalUserId}`, { exact: true }),
      ).toBeVisible();

      const overview = await apiFetch(
        adminPage,
        `/functions/v1/platform-admin/v1/admin/users/${normalUserId}/overview`,
      );
      expect(overview.status).toBe(200);
      expect(overview.body.data).toEqual(
        expect.objectContaining({
          profile: expect.objectContaining({ userId: normalUserId, status: 'deletion_pending' }),
          redemptions: expect.arrayContaining([
            expect.objectContaining({ status: 'redeemed', userId: normalUserId }),
          ]),
          feedback: expect.arrayContaining([
            expect.objectContaining({
              title: 'Release candidate journey feedback',
              status: 'open',
            }),
          ]),
          deletionRequests: expect.arrayContaining([
            expect.objectContaining({ status: 'pending' }),
          ]),
          auditTimeline: expect.arrayContaining([
            expect.objectContaining({ action: 'redemptions.redeem' }),
            expect.objectContaining({ action: 'account.deletion.requested' }),
          ]),
        }),
      );
      expect(JSON.stringify(overview.body)).not.toMatch(
        /sessionToken|csrfHash|tokenHash|password/i,
      );
      expect(overview.requestId).toBeTruthy();
    } finally {
      await adminContext.close();
    }
  });
});
