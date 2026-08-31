import { describe, expect, it } from 'vitest';

import { AdminClientError, createAdminClient, withIdempotencyKey } from '../src/index';

interface AdminHealthPayload {
  ok: boolean;
}

const adminHealthSchema = {
  parse(input: unknown): AdminHealthPayload {
    if (
      typeof input !== 'object' ||
      input === null ||
      !('ok' in input) ||
      typeof input.ok !== 'boolean'
    ) {
      throw new Error('Invalid admin health payload');
    }
    return { ok: input.ok };
  },
};

const requestId = '00000000-0000-4000-8000-000000000003';

describe('admin client transport', () => {
  it('attaches idempotency and CSRF headers without persistent storage', async () => {
    let receivedInit: RequestInit | undefined;
    const client = createAdminClient({
      baseUrl: 'https://api.example.test/',
      csrfToken: () => 'csrf-memory-token',
      fetch: async (_input, init) => {
        receivedInit = init;
        return new Response(JSON.stringify({ data: { ok: true }, requestId }), {
          headers: { 'content-type': 'application/json' },
          status: 200,
        });
      },
    });

    const init = withIdempotencyKey({ method: 'POST' }, 'idem-001');
    await expect(client.request('/v1/admin/operation', adminHealthSchema, init)).resolves.toEqual({
      data: { ok: true },
      requestId,
    });
    expect(init.idempotencyKey).toBe('idem-001');
    expect(new Headers(receivedInit?.headers).get('Idempotency-Key')).toBe('idem-001');
    expect(new Headers(receivedInit?.headers).get('x-csrf-token')).toBe('csrf-memory-token');
  });

  it('maps stable errors and rejects malformed responses', async () => {
    const client = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async () =>
        new Response(
          JSON.stringify({ error: { code: 'MFA_REQUIRED', message: 'MFA required.', requestId } }),
          {
            status: 403,
          },
        ),
    });

    await expect(client.request('/v1/admin/operation', adminHealthSchema)).rejects.toMatchObject<
      Partial<AdminClientError>
    >({
      code: 'MFA_REQUIRED',
      requestId,
      status: 403,
    });

    const malformedClient = createAdminClient({
      baseUrl: 'https://api.example.test',
      fetch: async () => new Response('not json', { status: 200 }),
    });
    await expect(
      malformedClient.request('/v1/admin/operation', adminHealthSchema),
    ).rejects.toMatchObject({
      code: 'MALFORMED_API_RESPONSE',
      status: 200,
    });
  });
});
