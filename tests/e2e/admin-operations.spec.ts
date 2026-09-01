import { expect, test } from '@playwright/test';

const accountPageOrigin = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:5173';
const adminPageOrigin = 'http://localhost:5174';
const roles = [
  { name: 'owner', email: 'owner.local@aisenhub.test', password: 'LocalOnly-Owner-2026!' },
  { name: 'admin', email: 'admin.local@aisenhub.test', password: 'LocalOnly-Admin-2026!' },
  { name: 'support', email: 'support.local@aisenhub.test', password: 'LocalOnly-Support-2026!' },
  {
    name: 'finance',
    email: 'finance.local@aisenhub.test',
    password: 'LocalOnly-Finance-2026!',
  },
] as const;

async function signInToAdmin(
  page: import('@playwright/test').Page,
  role: (typeof roles)[number],
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

async function adminApi(
  page: import('@playwright/test').Page,
  path: string,
): Promise<{ status: number; body: unknown }> {
  return page.evaluate(async (requestPath) => {
    const response = await fetch(requestPath);
    return { status: response.status, body: await response.json() };
  }, path);
}

test.describe('ADM-A read-only operations and RBAC', () => {
  for (const role of roles) {
    test(`${role.name} sees only its permitted operations`, async ({ page }) => {
      await signInToAdmin(page, role);

      await expect(page.getByText('Audit logs', { exact: true }).first()).toBeVisible();
      await expect(page.getByText('System health', { exact: true }).first()).toBeVisible();
      await expect(
        page.getByRole('button', { name: /Create|Publish|Refund|Grant|Revoke/ }),
      ).toHaveCount(0);

      const applications = await adminApi(
        page,
        '/functions/v1/platform-admin/v1/admin/applications',
      );
      if (role.name === 'finance') {
        expect(applications.status).toBe(403);
        await page.goto(`${adminPageOrigin}/applications`);
        await expect(page.getByText('Permission denied', { exact: true })).toBeVisible();
      } else {
        expect(applications.status).toBe(200);
        await page.goto(`${adminPageOrigin}/applications`);
        await expect(page.getByRole('heading', { name: 'Applications' }).first()).toBeVisible();
      }

      const audit = await adminApi(page, '/functions/v1/platform-admin/v1/admin/audit-logs');
      expect(audit.status).toBe(200);
    });
  }

  test('keeps unfinished Commerce truthful and proves direct forbidden access is backend-enforced', async ({
    page,
  }) => {
    await signInToAdmin(page, roles[3]);
    await expect(page.getByRole('menuitem', { name: 'Platform (coming soon)' })).toBeDisabled();
    const response = await adminApi(page, '/functions/v1/platform-admin/v1/admin/applications');
    expect(response.status).toBe(403);
  });
});
