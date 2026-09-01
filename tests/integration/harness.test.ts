import { expect, test, vi } from 'vitest';

import { TestHttpClient } from '../helpers/http';

test('integration HTTP client returns status and JSON body without cloud access', async () => {
  const fetchImplementation = vi.fn<typeof fetch>(
    async () =>
      new Response(JSON.stringify({ ok: true }), {
        headers: { 'content-type': 'application/json', 'x-request-id': 'integration-001' },
        status: 200,
      }),
  );
  const client = new TestHttpClient('http://127.0.0.1:54321', { fetchImplementation });

  const result = await client.request<{ ok: boolean }>('/v1/health');

  expect(result.status).toBe(200);
  expect(result.body).toEqual({ ok: true });
  expect(result.requestId).toBe('integration-001');
});
