import { errorResponse, requestId } from './platform-api.ts';

export type TelemetryContext = {
  readonly requestId: string;
  readonly route: string;
  readonly resultCode: string;
  readonly latencyMs: number;
  readonly userId?: string;
  readonly appId?: string;
};

const routePatterns: readonly [RegExp, string][] = [
  [/^\/v1\/admin\/.+$/, '/v1/admin/:resource'],
  [/^\/v1\/webhooks\/.+$/, '/v1/webhooks/:provider'],
  [/^\/v1\/apps\/.+$/, '/v1/apps/:slug'],
  [/^\/v1\/app\/access\/.+$/, '/v1/app/access/:feature'],
  [/^\/v1\/app(?:\/.*)?$/, '/v1/app'],
  [/^\/v1\/account(?:\/.*)?$/, '/v1/account'],
];

const sensitiveKey = /authorization|cookie|password|secret|token|code|card|cvv|payment|content/i;
const safeValue = /^[A-Za-z0-9._:/-]{1,128}$/;

export function normalizeTelemetryRoute(pathname: string): string {
  const pathnameValue = pathname.startsWith('/') ? pathname : `/${pathname}`;
  const marker = pathnameValue.lastIndexOf('/v1/');
  const route = marker >= 0 ? pathnameValue.slice(marker) : pathnameValue;
  if (route === '/' || route === '') return '/health';
  return routePatterns.find(([pattern]) => pattern.test(route))?.[1] ?? '/unknown';
}

export function resultCodeFromResponse(response: Response, body: string): string {
  try {
    const value: unknown = JSON.parse(body);
    if (value && typeof value === 'object' && 'error' in value) {
      const error = value.error;
      if (error && typeof error === 'object' && 'code' in error && typeof error.code === 'string') {
        return error.code.slice(0, 64);
      }
    }
  } catch {
    // A response body is never required for telemetry classification.
  }
  return response.status >= 400 ? `HTTP_${response.status}` : 'OK';
}

function metricName(route: string): string {
  if (route.startsWith('/v1/app/access/')) return 'entitlement_check_total';
  if (route === '/v1/app/redemptions') return 'redemption_total';
  if (route.startsWith('/v1/webhooks/')) return 'payment_webhook_total';
  if (route.startsWith('/v1/admin/')) return 'admin_operation_total';
  if (route === '/v1/app/feedback') return 'feedback_total';
  return 'platform_request_total';
}

export function safeStructuredLog(context: TelemetryContext): void {
  try {
    const payload: Record<string, string | number> = {
      event: 'platform.request',
      metric: metricName(context.route),
      requestId: context.requestId,
      route: context.route,
      resultCode: context.resultCode,
      latencyMs: Math.max(0, Math.round(context.latencyMs)),
    };
    for (const [key, value] of Object.entries({ userId: context.userId, appId: context.appId })) {
      if (value && !sensitiveKey.test(key) && safeValue.test(value)) payload[key] = value;
    }
    console.log(JSON.stringify(payload));
  } catch {
    // Observability must never change the request outcome.
  }
}

async function addResponseRequestId(response: Response, id: string): Promise<Response> {
  const headers = new Headers(response.headers);
  headers.set('x-request-id', id);
  const body = await response.text();
  if (!body || !response.headers.get('content-type')?.includes('application/json')) {
    return new Response(body || null, { status: response.status, headers });
  }

  try {
    const value: unknown = JSON.parse(body);
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      const envelope = { ...(value as Record<string, unknown>) };
      if (!('requestId' in envelope)) envelope.requestId = id;
      if (envelope.error && typeof envelope.error === 'object' && !Array.isArray(envelope.error)) {
        const error = { ...(envelope.error as Record<string, unknown>) };
        if (!('requestId' in error)) error.requestId = id;
        envelope.error = error;
      }
      return new Response(JSON.stringify(envelope), { status: response.status, headers });
    }
  } catch {
    // Preserve a non-JSON response body while still adding the trace header.
  }
  return new Response(body, { status: response.status, headers });
}

export async function withTelemetry(
  request: Request,
  handler: (request: Request) => Promise<Response>,
): Promise<Response> {
  const startedAt = performance.now();
  const id = requestId();
  const tracedHeaders = new Headers(request.headers);
  tracedHeaders.set('x-request-id', id);
  const tracedRequest = new Request(request, { headers: tracedHeaders });
  let response: Response;
  try {
    response = await handler(tracedRequest);
  } catch {
    response = errorResponse('INTERNAL_ERROR', 'The request could not be completed.', 500, id);
  }

  const responseId = response.headers.get('x-request-id')?.trim() || id;
  const body = await response.clone().text();
  const observed = await addResponseRequestId(response, responseId);
  safeStructuredLog({
    requestId: responseId,
    route: normalizeTelemetryRoute(new URL(request.url).pathname),
    resultCode: resultCodeFromResponse(observed, body),
    latencyMs: performance.now() - startedAt,
  });
  return observed;
}
