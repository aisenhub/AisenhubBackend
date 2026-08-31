import { describe, expect, it } from 'vitest';

import { createPlatformClient, PlatformClientError } from '../src/index';

interface HealthPayload {
  ok: boolean;
}

const healthSchema = {
  parse(input: unknown): HealthPayload {
    if (
      typeof input !== 'object' ||
      input === null ||
      !('ok' in input) ||
      typeof input.ok !== 'boolean'
    ) {
      throw new Error('Invalid health payload');
    }
    return { ok: input.ok };
  },
};

const requestId = '00000000-0000-4000-8000-000000000002';

describe('platform client transport', () => {
  it('uses credentialed requests, injects CSRF, and captures requestId', async () => {
    let receivedInit: RequestInit | undefined;
    const client = createPlatformClient({
      baseUrl: 'https://api.example.test/',
      csrfToken: () => 'csrf-memory-token',
      fetch: async (_input, init) => {
        receivedInit = init;
        return new Response(JSON.stringify({ data: { ok: true }, requestId }), {
          headers: { 'content-type': 'application/json', 'x-request-id': requestId },
          status: 200,
        });
      },
    });

    await expect(client.request('/v1/health', healthSchema)).resolves.toEqual({
      data: { ok: true },
      requestId,
    });
    expect(receivedInit?.credentials).toBe('include');
    expect(new Headers(receivedInit?.headers).get('x-csrf-token')).toBe('csrf-memory-token');
  });

  it('maps stable API errors and rejects malformed success payloads safely', async () => {
    const errorClient = createPlatformClient({
      baseUrl: 'https://api.example.test',
      fetch: async () =>
        new Response(
          JSON.stringify({
            error: { code: 'VALIDATION_ERROR', message: 'Invalid input.', requestId },
          }),
          { status: 422 },
        ),
    });

    await expect(errorClient.request('/v1/me', healthSchema)).rejects.toMatchObject<
      Partial<PlatformClientError>
    >({
      code: 'VALIDATION_ERROR',
      requestId,
      status: 422,
    });

    const malformedClient = createPlatformClient({
      baseUrl: 'https://api.example.test',
      fetch: async () => new Response(JSON.stringify({ data: { ok: 'yes' }, requestId })),
    });
    await expect(malformedClient.request('/v1/me', healthSchema)).rejects.toMatchObject({
      code: 'MALFORMED_API_RESPONSE',
      status: 200,
    });
  });
});
