import { describe, expect, test, vi } from 'vitest';

import { TestHttpClient } from './helpers/http';
import { createTestRoleContext, testRoles } from './helpers/role-context';

describe('test harness primitives', () => {
  test('exposes anon, authenticated, and service role contexts', () => {
    expect(testRoles.map((role) => createTestRoleContext(role).role)).toEqual([
      'anon',
      'authenticated',
      'service_role',
    ]);
  });

  test('preserves cookies, CSRF, credentials, and requestId', async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (_input, init) => {
      const headers = new Headers((init as RequestInit).headers);
      expect(headers.get('x-csrf-token')).toBe('csrf-test');
      expect((init as RequestInit).credentials).toBe('include');
      if (fetchImplementation.mock.calls.length > 1) {
        expect(headers.get('cookie')).toBe('session=first');
      }

      return new Response(JSON.stringify({ ok: true }), {
        headers: {
          'content-type': 'application/json',
          'set-cookie': 'session=first; Path=/; HttpOnly',
          'x-request-id': 'req-test-001',
        },
        status: 200,
      });
    });
    const client = new TestHttpClient('http://127.0.0.1:54321', {
      csrfToken: 'csrf-test',
      fetchImplementation,
    });

    const first = await client.request<{ ok: boolean }>('/v1/test');
    expect(first.requestId).toBe('req-test-001');

    await client.request('/v1/test', {
      headers: {
        cookie: 'session=first',
      },
    });
    expect(fetchImplementation).toHaveBeenCalledTimes(2);
  });
});
