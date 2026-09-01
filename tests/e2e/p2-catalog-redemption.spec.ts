import { expect, test } from '@playwright/test';

const accountPageOrigin = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:5173';
const user = {
  email: 'normal-user.local@aisenhub.test',
  password: 'LocalOnly-NormalUser-2026!',
};

type BrowserApiInit = {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
};

async function signIn(page: import('@playwright/test').Page): Promise<void> {
  await page.goto(accountPageOrigin);
  await expect(page.getByRole('heading', { name: 'One account for your tools.' })).toBeVisible();
  await page.getByLabel('Email address').fill(user.email);
  await page.getByLabel('Password').fill(user.password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('heading', { name: /Welcome back/ })).toBeVisible();
}

async function apiFetch(
  page: import('@playwright/test').Page,
  path: string,
  init?: BrowserApiInit,
) {
  return page.evaluate(
    async ({ path, init }) => {
      const response = await fetch(path, init);
      return { status: response.status, body: await response.json() };
    },
    { path, init },
  );
}

test.describe('P2 catalog, entitlement, and redemption flows', () => {
  test('shows the public catalog and the normal user access projection', async ({
    page,
    request,
  }) => {
    await signIn(page);

    const catalog = await apiFetch(page, '/functions/v1/platform-public/v1/products/public');
    expect(catalog.status).toBe(200);
    expect(catalog.body.data.products).toEqual([
      {
        sku: 'AISENLENS_LIFETIME',
        name: 'AisenLens Lifetime',
        billingType: 'one_time',
        version: 1,
      },
    ]);
    expect(JSON.stringify(catalog.body)).not.toMatch(/price|hash|grant|audit/i);

    const sessionCookie = (await page.context().cookies()).find(
      (cookie) => cookie.name === '__Host-aisenhub_session',
    );
    expect(sessionCookie?.value).toBeTruthy();
    const access = await request.get(
      'http://127.0.0.1:54321/functions/v1/platform-api/v1/access/aisenlens.app.access',
      {
        headers: {
          Origin: 'http://localhost:5175',
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
      expiresAt: null,
    });
  });

  test('lists server-resolved entitlements and rejects invalid redemption safely', async ({
    page,
  }) => {
    await signIn(page);

    const entitlements = await apiFetch(page, '/functions/v1/platform-api/v1/me/entitlements', {
      headers: { 'X-AisenHub-App': 'account' },
    });
    expect(entitlements.status).toBe(200);
    expect(entitlements.body.data.entitlements).toEqual([
      {
        feature: 'aisenlens.app.access',
        value: true,
        sourceProduct: 'AISENLENS_LIFETIME',
        expiresAt: null,
      },
      {
        feature: 'aisenlens.supporter_feedback',
        value: true,
        sourceProduct: 'AISENLENS_LIFETIME',
        expiresAt: null,
      },
    ]);

    const session = await apiFetch(page, '/functions/v1/platform-api/v1/session', {
      headers: { 'X-AisenHub-App': 'account' },
    });
    expect(session.status).toBe(200);
    const redemption = await apiFetch(page, '/functions/v1/platform-api/v1/redemptions', {
      method: 'POST',
      headers: {
        'X-AisenHub-App': 'account',
        'X-CSRF-Token': session.body.data.csrfToken,
        'Idempotency-Key': 'p2-invalid-redemption-1',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ code: 'not-a-real-local-code' }),
    });
    expect(redemption.status).toBe(409);
    expect(redemption.body.error.code).toBe('REDEMPTION_UNAVAILABLE');
    expect(JSON.stringify(redemption.body)).not.toMatch(/SQLSTATE|token|hash|stack|secret/i);
  });

  test('rejects forged application declarations and mutation requests without CSRF', async ({
    request,
  }) => {
    const forged = await request.get(
      'http://127.0.0.1:54321/functions/v1/platform-api/v1/access/aisenlens.app.access',
      { headers: { Origin: 'http://localhost:5173', 'X-AisenHub-App': 'admin' } },
    );
    expect(forged.status()).toBe(403);
    expect((await forged.json()).error.code).toBe('APP_ORIGIN_MISMATCH');
  });
});
