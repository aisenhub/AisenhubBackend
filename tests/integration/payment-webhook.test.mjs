import { afterAll, afterEach, describe, expect, it, vi } from 'vitest';

const originalFetch = globalThis.fetch;
const secret = 'local-webhook-secret-0123456789';
const requestFixture = {
  id: '00000000-0000-4000-8000-000000000101',
  type: 'payment.succeeded',
  data: {
    paymentId: '00000000-0000-4000-8000-000000000201',
    orderId: '00000000-0000-4000-8000-000000000301',
    amount: 1000,
    currency: 'USD',
    occurredAt: '2026-09-02T11:00:00.000Z',
    payloadSummary: { providerStatus: 'approved', channel: 'local' },
  },
};
let rpcResult = {
  status: 'fulfilled',
  orderId: requestFixture.data.orderId,
  paymentId: requestFixture.data.paymentId,
  paymentEventId: '00000000-0000-4000-8000-000000000401',
  idempotent: false,
};
let rpcCalls = [];

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
    rpcCalls.push({ url: String(url), body: JSON.parse(init.body) });
    return new Response(JSON.stringify([rpcResult]), {
      headers: { 'content-type': 'application/json' },
    });
  }),
);

const { handleWebhook } = await import('../../supabase/functions/payment-webhook/index.ts');
const { signWebhookPayload } = await import('../../supabase/functions/payment-webhook/provider.ts');

async function signedRequest(
  payload,
  timestamp = Math.floor(Date.now() / 1000),
  body = JSON.stringify(payload),
) {
  const signature = await signWebhookPayload(body, timestamp, secret);
  return new Request('http://local.supabase/v1/webhooks/local', {
    method: 'POST',
    headers: { 'x-aisenhub-webhook-signature': `t=${timestamp},v1=${signature}` },
    body,
  });
}

afterAll(() => {
  globalThis.fetch = originalFetch;
  vi.unstubAllGlobals();
});

afterEach(() => {
  rpcCalls = [];
  rpcResult = {
    status: 'fulfilled',
    orderId: requestFixture.data.orderId,
    paymentId: requestFixture.data.paymentId,
    paymentEventId: '00000000-0000-4000-8000-000000000401',
    idempotent: false,
  };
});

describe('signed local payment webhook', () => {
  it('verifies the raw body, normalizes the event, and dispatches it', async () => {
    const response = await handleWebhook(await signedRequest(requestFixture));
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.webhook.status).toBe('fulfilled');
    expect(body.requestId).toBe(response.headers.get('x-request-id'));
    expect(rpcCalls).toHaveLength(1);
    expect(rpcCalls[0].url).toContain('/rest/v1/rpc/receive_payment_webhook_event');
    expect(rpcCalls[0].body).toMatchObject({
      p_provider: 'local',
      p_external_event_id: requestFixture.id,
      p_event_type: 'payment.succeeded',
      p_payload_summary: requestFixture.data.payloadSummary,
    });
  });

  it('rejects forged and expired signatures before database access', async () => {
    const request = await signedRequest(requestFixture);
    request.headers.set('x-aisenhub-webhook-signature', 't=invalid,v1=invalid');
    const forged = await handleWebhook(request);
    const expired = await handleWebhook(
      await signedRequest(requestFixture, Math.floor(Date.now() / 1000) - 301),
    );

    expect(forged.status).toBe(401);
    expect(expired.status).toBe(401);
    expect(rpcCalls).toHaveLength(0);
  });

  it('rejects malformed or sensitive payloads after signature verification', async () => {
    const malformed = await handleWebhook(await signedRequest(requestFixture, undefined, '{'));
    const sensitivePayload = structuredClone(requestFixture);
    sensitivePayload.data.payloadSummary = { nested: { token: 'must-not-pass' } };
    const sensitive = await handleWebhook(await signedRequest(sensitivePayload));

    expect(malformed.status).toBe(400);
    expect(sensitive.status).toBe(400);
    expect(rpcCalls).toHaveLength(0);
  });

  it('returns safe idempotent and ignored outcomes from the domain boundary', async () => {
    rpcResult = { ...rpcResult, status: 'processed', idempotent: true };
    const duplicate = await handleWebhook(await signedRequest(requestFixture));
    rpcResult = { ...rpcResult, status: 'ignored', idempotent: false };
    const outOfOrder = await handleWebhook(
      await signedRequest({
        ...requestFixture,
        id: '00000000-0000-4000-8000-000000000102',
        type: 'payment.failed',
      }),
    );

    expect((await duplicate.json()).data.webhook).toMatchObject({
      status: 'processed',
      idempotent: true,
    });
    expect((await outOfOrder.json()).data.webhook).toMatchObject({ status: 'ignored' });
    expect(rpcCalls).toHaveLength(2);
  });

  it('does not require or interpret a user JWT', async () => {
    const request = await signedRequest(requestFixture);
    request.headers.set('authorization', 'Bearer not-a-user-token');
    const response = await handleWebhook(request);

    expect(response.status).toBe(200);
    expect(rpcCalls).toHaveLength(1);
  });
});
