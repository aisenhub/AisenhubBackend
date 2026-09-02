import {
  errorResponse,
  jsonResponse,
  requestIdFromRequest,
  serviceRpc,
  ServiceRpcError,
} from '../_shared/platform-api.ts';
import { withTelemetry } from '../_shared/telemetry.ts';
import {
  isProviderName,
  providerForName,
  verifyWebhookSignature,
  webhookSecretFromEnv,
  WebhookPayloadError,
  type NormalizedPaymentWebhookEvent,
} from './provider.ts';

const signatureHeader = 'x-aisenhub-webhook-signature';
const webhookPath = /^\/v1\/webhooks\/([a-z0-9]+(?:[_-][a-z0-9]+)*)$/;

type WebhookResult = {
  readonly status: string;
  readonly orderId?: string;
  readonly paymentId?: string;
  readonly paymentEventId?: string;
  readonly idempotent?: boolean;
};

function providerName(request: Request): string | null {
  const match = new URL(request.url).pathname.match(webhookPath);
  return match?.[1] ?? null;
}

function processingError(id: string, error: unknown): Response {
  if (error instanceof ServiceRpcError && error.databaseCode === '23514') {
    return errorResponse(
      'WEBHOOK_EVENT_MISMATCH',
      'The payment event could not be accepted.',
      400,
      id,
    );
  }
  if (error instanceof ServiceRpcError && error.databaseCode === '22023') {
    return errorResponse(
      'WEBHOOK_EVENT_INVALID',
      'The payment event could not be accepted.',
      400,
      id,
    );
  }
  return errorResponse(
    'WEBHOOK_PROCESSING_FAILED',
    'The payment event could not be processed and may be retried.',
    502,
    id,
  );
}

export async function handleWebhook(request: Request): Promise<Response> {
  const id = requestIdFromRequest(request);
  if (request.method !== 'POST') {
    return errorResponse('METHOD_NOT_ALLOWED', 'Only POST is supported.', 405, id);
  }

  const provider = providerName(request);
  if (!provider || !isProviderName(provider) || !providerForName(provider)) {
    return errorResponse(
      'WEBHOOK_PROVIDER_NOT_FOUND',
      'The payment provider is not supported.',
      404,
      id,
    );
  }

  const rawBody = await request.text();
  const secret = webhookSecretFromEnv(provider, (name) => Deno.env.get(name));
  const validSignature = await verifyWebhookSignature(
    rawBody,
    request.headers.get(signatureHeader),
    secret,
  );
  if (!validSignature) {
    return errorResponse('WEBHOOK_SIGNATURE_INVALID', 'The webhook signature is invalid.', 401, id);
  }

  let normalized: NormalizedPaymentWebhookEvent;
  try {
    const payload: unknown = JSON.parse(rawBody);
    const adapter = providerForName(provider);
    if (!adapter) {
      return errorResponse(
        'WEBHOOK_PROVIDER_NOT_FOUND',
        'The payment provider is not supported.',
        404,
        id,
      );
    }
    normalized = adapter.normalize(payload);
  } catch (error) {
    if (error instanceof WebhookPayloadError || error instanceof SyntaxError) {
      return errorResponse('WEBHOOK_PAYLOAD_INVALID', 'The webhook payload is invalid.', 400, id);
    }
    return processingError(id, error);
  }

  try {
    const rows = await serviceRpc<WebhookResult>('receive_payment_webhook_event', {
      p_payment_id: normalized.paymentId,
      p_order_id: normalized.orderId,
      p_provider: normalized.provider,
      p_external_event_id: normalized.externalEventId,
      p_event_type: normalized.eventType,
      p_currency: normalized.currency,
      p_amount: normalized.amount,
      p_payload_summary: normalized.payloadSummary,
      p_occurred_at: normalized.occurredAt,
    });
    const result = rows.length === 1 ? rows[0] : null;
    if (!result || typeof result.status !== 'string') return processingError(id, null);
    return jsonResponse({ webhook: result }, 200, id);
  } catch (error) {
    return processingError(id, error);
  }
}

if (typeof Deno !== 'undefined' && typeof Deno.serve === 'function') {
  Deno.serve((request) => withTelemetry(request, handleWebhook));
}
