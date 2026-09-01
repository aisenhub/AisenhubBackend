import { expect, test } from '@playwright/test';

const authApiUrl = 'http://127.0.0.1:54321';
const platformApiUrl = `${authApiUrl}/functions/v1/platform-api`;
const accountPageOrigin = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:5173';
const registeredAccountOrigin = 'http://localhost:5173';
const user = {
  email: 'normal-user.local@aisenhub.test',
  password: 'LocalOnly-NormalUser-2026!',
};

async function signIn(page: import('@playwright/test').Page): Promise<void> {
  await page.goto(accountPageOrigin);
  await expect(page.getByRole('heading', { name: 'One account for your tools.' })).toBeVisible();
  await page.waitForTimeout(1000);
  await page.getByLabel('Email address').fill(user.email);
  await page.getByLabel('Password').fill(user.password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('heading', { name: /Welcome back/ })).toBeVisible();
}

test.describe('P1 platform sessions', () => {
  test('logs in, isolates sessions, and logs out one browser only', async ({ browser, page }) => {
    await signIn(page);
    const firstCookies = await page.context().cookies(accountPageOrigin);
    const firstSession = firstCookies.find((cookie) => cookie.name === '__Host-aisenhub_session');
    expect(firstSession).toMatchObject({
      httpOnly: true,
      secure: true,
      sameSite: 'Lax',
      path: '/',
    });
    expect(firstSession?.domain).toBe('localhost');
    expect(await page.evaluate(() => document.cookie)).toBe('');

    const secondContext = await browser.newContext();
    const secondPage = await secondContext.newPage();
    try {
      await signIn(secondPage);
      const secondCookies = await secondContext.cookies(accountPageOrigin);
      const secondSession = secondCookies.find(
        (cookie) => cookie.name === '__Host-aisenhub_session',
      );
      expect(secondSession?.value).not.toBe(firstSession?.value);

      await page.getByRole('button', { name: 'Sign out' }).click();
      await expect(
        page.getByRole('heading', { name: 'One account for your tools.' }),
      ).toBeVisible();

      await secondPage.reload();
      await expect(secondPage.getByRole('heading', { name: /Welcome back/ })).toBeVisible();
    } finally {
      await secondContext.close();
    }
  });

  test('rejects invalid Origin and forged application declarations', async ({ request }) => {
    const unregistered = await request.get(`${platformApiUrl}/v1/session`, {
      headers: { Origin: 'https://attacker.example' },
    });
    expect(unregistered.status()).toBe(403);
    expect((await unregistered.json()).error.code).toBe('ORIGIN_NOT_ALLOWED');

    const forged = await request.get(`${platformApiUrl}/v1/session`, {
      headers: { Origin: registeredAccountOrigin, 'X-AisenHub-App': 'admin' },
    });
    expect(forged.status()).toBe(403);
    expect((await forged.json()).error.code).toBe('APP_ORIGIN_MISMATCH');
  });

  test('returns 401 for a revoked or unknown session without internal details', async ({
    page,
  }) => {
    await page.goto(accountPageOrigin);
    await page.context().addCookies([
      {
        name: '__Host-aisenhub_session',
        value: 'invalid-session-token',
        domain: 'localhost',
        path: '/',
        httpOnly: true,
        secure: true,
        sameSite: 'Lax',
      },
    ]);
    await page.reload();
    await expect(page.getByRole('alert')).toContainText('session has expired');
    await expect(page.getByRole('alert')).not.toContainText('token_hash');
  });
});
