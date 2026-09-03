import { expect, test } from '@playwright/test';

const accountOrigin = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:5173';
const adminOrigin = process.env.PLAYWRIGHT_ADMIN_BASE_URL ?? 'http://localhost:5174';

type RecordedRequest = {
  readonly origin: string | null;
  readonly authorization: string | null;
};

test('R3-T008 keeps Account and Admin application context independent', async ({ browser }) => {
  const context = await browser.newContext();
  const accountPage = await context.newPage();
  const adminPage = await context.newPage();
  const calls: RecordedRequest[] = [];

  await accountPage.route('**/functions/v1/platform-api/v1/app/context', async (route) => {
    calls.push({
      origin: route.request().headers().origin ?? null,
      authorization: route.request().headers().authorization ?? null,
    });
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: {
          application: { id: 'account-app', slug: 'account', status: 'active' },
          membership: { id: 'account-membership', status: 'active' },
        },
        requestId: 'account-request',
      }),
    });
  });
  await adminPage.route('**/functions/v1/platform-admin/v1/admin/session', async (route) => {
    calls.push({
      origin: route.request().headers().origin ?? null,
      authorization: route.request().headers().authorization ?? null,
    });
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: {
          authenticated: true,
          identity: { userId: 'shared-user', displayName: 'Shared User' },
          role: 'owner',
          aal: 'aal2',
          mfaState: 'verified',
          expiresAt: '2026-09-03T12:00:00.000Z',
        },
        requestId: 'admin-request',
      }),
    });
  });

  try {
    await accountPage.goto(accountOrigin);
    await accountPage.evaluate(async () => {
      const response = await fetch('/functions/v1/platform-api/v1/app/context', {
        headers: { Authorization: 'Bearer account-token' },
      });
      if (!response.ok) throw new Error(`Account context failed: ${response.status}`);
    });
    await adminPage.goto(`${adminOrigin}/overview`);
    await adminPage.evaluate(async () => {
      const response = await fetch('/functions/v1/platform-admin/v1/admin/session', {
        headers: { Authorization: 'Bearer admin-token' },
      });
      if (!response.ok) throw new Error(`Admin context failed: ${response.status}`);
    });

    expect(calls.filter((call) => call.authorization !== null)).toEqual([
      { origin: null, authorization: 'Bearer account-token' },
      { origin: null, authorization: 'Bearer admin-token' },
    ]);
    expect(await accountPage.evaluate(() => document.cookie)).toBe('');
    expect(await adminPage.evaluate(() => document.cookie)).toBe('');
    expect(await context.cookies()).toEqual([]);
  } finally {
    await context.close();
  }
});
