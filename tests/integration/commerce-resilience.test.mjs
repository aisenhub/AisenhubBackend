import { afterAll, afterEach, describe, expect, it, vi } from 'vitest';

const originalFetch = globalThis.fetch;
const secret = 'local-commerce-resilience-secret-0123456789';
const paymentId = '00000000-0000-4000-8000-000000000201';
const orderId = '00000000-0000-4000-8000-000000000301';
const calls = [];
let rpcResults = [];

vi.stubGlobal('Deno', {
  env: {
    get(name) {
      return {
        SUPABASE_URL: 'http://local.supabase',
        SUPABASE_ANON_KEY: 'local-anon-key',
        SUPABASE_SERVICE_ROLE_KEY: 'local-service-role-key',
        PAYMENT_WEBHOOK_SECRET_LOCAL: secret,
      }[name];
    },
  },
});
vi.stubGlobal(
  'fetch',
  vi.fn(async (url, init) => {
    calls.push({ url: String(url), body: JSON.parse(init.body) });
    return new Response(JSON.stringify([rpcResults.shift() ?? null]), {
      headers: { 'content-type': 'application/json' },
    });
  }),
);

const { handleWebhook } = await import('../../supabase/functions/payment-webhook/index.ts');
const { signWebhookPayload } = await import('../../supabase/functions/payment-webhook/provider.ts');

async function signedRequest(event, timestamp = Math.floor(Date.now() / 1000)) {
  const body = JSON.stringify(event);
  const signature = await signWebhookPayload(body, timestamp, secret);
  return new Request('http://local.supabase/v1/webhooks/local', {
    method: 'POST',
    headers: { 'x-aisenhub-webhook-signature': `t=${timestamp},v1=${signature}` },
    body,
  });
}

function event(id, type, occurredAt) {
  return {
    id,
    type,
    data: {
      paymentId,
      orderId,
      amount: 2000,
      currency: 'USD',
      occurredAt,
      payloadSummary: { providerStatus: 'approved', channel: 'local' },
    },
  };
}

afterAll(() => {
  globalThis.fetch = originalFetch;
  vi.unstubAllGlobals();
});

afterEach(() => {
  calls.length = 0;
  rpcResults = [];
});

describe('Commerce resilience at the signed payment boundary', () => {
  it('propagates fulfillment, duplicate, stale-event, and exception outcomes safely', async () => {
    rpcResults = [
      {
        status: 'fulfilled',
        orderId,
        paymentId,
        paymentEventId: '00000000-0000-4000-8000-000000000401',
        idempotent: false,
      },
      { status: 'processed', orderId, paymentId, idempotent: true },
      { status: 'ignored', orderId, paymentId, idempotent: false },
      {
        status: 'exception',
        exceptionType: 'late_payment_after_cancel',
        orderId,
        paymentId,
        idempotent: false,
      },
    ];

    const responses = await Promise.all([
      handleWebhook(
        await signedRequest(
          event('resilience-flow-001', 'payment.succeeded', '2026-09-02T11:00:00Z'),
        ),
      ),
      handleWebhook(
        await signedRequest(
          event('resilience-flow-001', 'payment.succeeded', '2026-09-02T11:00:00Z'),
        ),
      ),
      handleWebhook(
        await signedRequest(event('resilience-flow-002', 'payment.failed', '2026-09-02T11:01:00Z')),
      ),
      handleWebhook(
        await signedRequest(
          event('resilience-flow-003', 'payment.succeeded', '2026-09-02T11:02:00Z'),
        ),
      ),
    ]);
    const bodies = await Promise.all(responses.map((response) => response.json()));

    expect(responses.map((response) => response.status)).toEqual([200, 200, 200, 200]);
    expect(bodies.map((body) => body.data.webhook.status)).toEqual([
      'fulfilled',
      'processed',
      'ignored',
      'exception',
    ]);
    expect(bodies[1].data.webhook.idempotent).toBe(true);
    expect(bodies[3].data.webhook.exceptionType).toBe('late_payment_after_cancel');
    expect(calls).toHaveLength(4);
    expect(
      calls.every((call) => call.url.endsWith('/rest/v1/rpc/receive_payment_webhook_event')),
    ).toBe(true);
    expect(calls.map((call) => call.body.p_external_event_id)).toEqual([
      'resilience-flow-001',
      'resilience-flow-001',
      'resilience-flow-002',
      'resilience-flow-003',
    ]);
    expect(calls[0].body).toMatchObject({
      p_payment_id: paymentId,
      p_order_id: orderId,
      p_provider: 'local',
      p_event_type: 'payment.succeeded',
      p_payload_summary: { providerStatus: 'approved', channel: 'local' },
    });
    expect(JSON.stringify(calls)).not.toContain(secret);
  });

  it('keeps a retryable domain failure opaque and traceable by requestId', async () => {
    rpcResults = [null];
    const response = await handleWebhook(
      await signedRequest(
        event('resilience-flow-retry', 'payment.succeeded', '2026-09-02T11:03:00Z'),
      ),
    );
    const body = await response.json();

    expect(response.status).toBe(502);
    expect(body.error.code).toBe('WEBHOOK_PROCESSING_FAILED');
    expect(body.error.requestId).toBe(response.headers.get('x-request-id'));
    expect(body.error.message).not.toContain('local-service-role-key');
  });
});
