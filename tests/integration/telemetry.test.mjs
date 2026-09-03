import { afterEach, describe, expect, it, vi } from 'vitest';

const logs = [];
const logSpy = vi.spyOn(console, 'log').mockImplementation((value) => logs.push(String(value)));

const { resultCodeFromResponse, safeStructuredLog, withTelemetry } =
  await import('../../supabase/functions/_shared/telemetry.ts');

afterEach(() => {
  logs.length = 0;
  logSpy.mockImplementation((value) => logs.push(String(value)));
});

describe('request telemetry boundary', () => {
  it('propagates one request id to headers and JSON responses', async () => {
    let handlerRequestId;
    const response = await withTelemetry(
      new Request('http://local.supabase/functions/v1/platform-api/v1/account/me'),
      async (request) => {
        handlerRequestId = request.headers.get('x-request-id');
        return new Response(JSON.stringify({ data: { ok: true }, requestId: handlerRequestId }), {
          headers: { 'content-type': 'application/json', 'x-request-id': handlerRequestId },
        });
      },
    );
    const body = await response.json();

    expect(response.headers.get('x-request-id')).toBe(handlerRequestId);
    expect(body.requestId).toBe(handlerRequestId);
    expect(JSON.parse(logs[0])).toMatchObject({
      event: 'platform.request',
      route: '/v1/account',
      resultCode: 'OK',
    });
  });

  it('classifies error codes without logging response bodies', async () => {
    const response = await withTelemetry(
      new Request('http://local.supabase/functions/v1/webhooks/local'),
      async () =>
        new Response(
          JSON.stringify({
            error: { code: 'WEBHOOK_SIGNATURE_INVALID', message: 'do not log this body' },
          }),
          { status: 401, headers: { 'content-type': 'application/json' } },
        ),
    );
    const body = await response.json();

    expect(resultCodeFromResponse(response, JSON.stringify(body))).toBe(
      'WEBHOOK_SIGNATURE_INVALID',
    );
    expect(logs[0]).not.toContain('do not log this body');
    expect(logs[0]).not.toContain('authorization');
  });

  it('survives logger failure and bounds optional identity fields', async () => {
    logSpy.mockImplementation(() => {
      throw new Error('logger unavailable');
    });
    expect(() =>
      safeStructuredLog({
        requestId: 'trace-002',
        route: '/v1/me',
        resultCode: 'OK',
        latencyMs: 2,
        userId: 'user-001',
        appId: 'app-001',
      }),
    ).not.toThrow();

    const response = await withTelemetry(
      new Request('http://local.supabase/functions/v1/health'),
      async () => new Response('ok', { status: 200 }),
    );
    expect(response.headers.get('x-request-id')).toBeTruthy();
  });
});
