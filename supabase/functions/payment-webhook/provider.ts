export type NormalizedPaymentWebhookEvent = {
  readonly paymentId: string;
  readonly orderId: string;
  readonly provider: string;
  readonly externalEventId: string;
  readonly eventType: string;
  readonly currency: string;
  readonly amount: number;
  readonly occurredAt: string;
  readonly payloadSummary: Record<string, unknown>;
};

export type PaymentWebhookProvider = {
  readonly name: string;
  normalize(payload: unknown): NormalizedPaymentWebhookEvent;
};

export class WebhookPayloadError extends Error {
  constructor(message = 'The webhook payload is invalid.') {
    super(message);
    this.name = 'WebhookPayloadError';
  }
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const eventIdPattern = /^\S+$/;
const eventTypePattern = /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/;
const currencyPattern = /^[A-Z]{3}$/;
const providerPattern = /^[a-z0-9]+(?:[_-][a-z0-9]+)*$/;
const sensitiveKeys = new Set([
  'authorization',
  'card_number',
  'card_expiry',
  'cvv',
  'cvc',
  'pan',
  'password',
  'secret',
  'token',
  'access_token',
  'refresh_token',
  'payment_method',
  'payment_method_token',
  'credential',
  'credentials',
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requiredRecord(value: unknown, field: string): Record<string, unknown> {
  if (!isRecord(value)) throw new WebhookPayloadError(`The webhook ${field} is invalid.`);
  return value;
}

function requiredString(value: unknown, field: string, pattern?: RegExp, max = 200): string {
  if (typeof value !== 'string') throw new WebhookPayloadError(`The webhook ${field} is invalid.`);
  const normalized = value.trim();
  if (normalized === '' || normalized.length > max || (pattern && !pattern.test(normalized))) {
    throw new WebhookPayloadError(`The webhook ${field} is invalid.`);
  }
  return normalized;
}

function safeSummary(value: unknown): Record<string, unknown> {
  const summary = requiredRecord(value ?? {}, 'payload summary');
  const visit = (child: unknown): boolean => {
    if (Array.isArray(child)) return child.every(visit);
    if (!isRecord(child)) return true;
    return Object.entries(child).every(
      ([key, nested]) => !sensitiveKeys.has(key.toLowerCase()) && visit(nested),
    );
  };
  if (!visit(summary)) throw new WebhookPayloadError('The webhook payload summary is sensitive.');
  if (new TextEncoder().encode(JSON.stringify(summary)).byteLength > 32768) {
    throw new WebhookPayloadError('The webhook payload summary is too large.');
  }
  return summary;
}

function normalizeLocalPayload(payload: unknown): NormalizedPaymentWebhookEvent {
  const envelope = requiredRecord(payload, 'payload');
  const data = requiredRecord(envelope.data, 'data');
  const paymentId = requiredString(data.paymentId, 'paymentId', uuidPattern);
  const orderId = requiredString(data.orderId, 'orderId', uuidPattern);
  const externalEventId = requiredString(envelope.id, 'event id', eventIdPattern);
  const eventType = requiredString(envelope.type, 'event type', eventTypePattern);
  const currency = requiredString(data.currency, 'currency', currencyPattern, 3);
  const occurredAt = requiredString(data.occurredAt, 'occurredAt', undefined, 40);
  const occurredTime = Date.parse(occurredAt);
  if (!Number.isFinite(occurredTime)) {
    throw new WebhookPayloadError('The webhook occurredAt is invalid.');
  }
  if (!Number.isSafeInteger(data.amount) || Number(data.amount) < 0) {
    throw new WebhookPayloadError('The webhook amount is invalid.');
  }

  return {
    paymentId,
    orderId,
    provider: 'local',
    externalEventId,
    eventType,
    currency,
    amount: Number(data.amount),
    occurredAt: new Date(occurredTime).toISOString(),
    payloadSummary: safeSummary(data.payloadSummary),
  };
}

export class LocalFakePaymentProvider implements PaymentWebhookProvider {
  readonly name = 'local';

  normalize(payload: unknown): NormalizedPaymentWebhookEvent {
    return normalizeLocalPayload(payload);
  }
}

export function providerForName(name: string): PaymentWebhookProvider | null {
  if (!providerPattern.test(name)) return null;
  return name === 'local' ? new LocalFakePaymentProvider() : null;
}

export function isProviderName(value: string): boolean {
  return providerPattern.test(value);
}

export function webhookSecretFromEnv(
  provider: string,
  getEnv: (name: string) => string | undefined,
): string | undefined {
  const suffix = provider.toUpperCase().replaceAll('-', '_');
  return getEnv(`PAYMENT_WEBHOOK_SECRET_${suffix}`) ?? getEnv('PAYMENT_WEBHOOK_SECRET');
}

export async function signWebhookPayload(
  rawBody: string,
  timestamp: number,
  secret: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(`${timestamp}.${rawBody}`),
  );
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function hexToBytes(value: string): Uint8Array | null {
  if (!/^[0-9a-f]{64}$/i.test(value)) return null;
  const bytes = new Uint8Array(32);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left[index] ^ right[index];
  return difference === 0;
}

export async function verifyWebhookSignature(
  rawBody: string,
  header: string | null,
  secret: string | undefined,
  nowMs = Date.now(),
  toleranceSeconds = 300,
): Promise<boolean> {
  if (!secret || secret.length < 16 || !header) return false;
  const fields = new Map(
    header
      .split(',')
      .map((part) => part.trim().split('=', 2))
      .filter(([key, value]) => key !== '' && value !== '') as [string, string][],
  );
  const timestamp = Number(fields.get('t'));
  const supplied = hexToBytes(fields.get('v1') ?? '');
  if (!Number.isSafeInteger(timestamp) || !supplied) return false;
  if (Math.abs(nowMs - timestamp * 1000) > toleranceSeconds * 1000) return false;
  const expected = hexToBytes(await signWebhookPayload(rawBody, timestamp, secret));
  return expected !== null && constantTimeEqual(expected, supplied);
}
