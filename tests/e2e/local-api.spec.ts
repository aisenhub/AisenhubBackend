import { expect, test } from '@playwright/test';

test('local platform API is reachable', async ({ request }) => {
  const response = await request.get('/');
  expect(response.status()).toBeLessThan(500);
});
