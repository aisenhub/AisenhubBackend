export function requestId(): string {
  return crypto.randomUUID();
}

export function requestIdFromRequest(request: Request): string {
  const value = request.headers.get('x-request-id')?.trim() ?? '';
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value
    : requestId();
}

export function jsonResponse(
  data: unknown,
  status: number,
  id: string,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify({ data, requestId: id }), {
    status,
    headers: {
      'content-type': 'application/json',
      'x-request-id': id,
      ...headers,
    },
  });
}

export function errorResponse(code: string, message: string, status: number, id: string): Response {
  return new Response(
    JSON.stringify({
      error: {
        code,
        message,
        requestId: id,
      },
    }),
    {
      status,
      headers: {
        'content-type': 'application/json',
        'x-request-id': id,
      },
    },
  );
}

export function bearerToken(request: Request): string | null {
  const value = request.headers.get('authorization');
  if (!value?.startsWith('Bearer ')) return null;
  const token = value.slice('Bearer '.length).trim();
  return token === '' ? null : token;
}

export function apiPath(request: Request): string {
  const pathname = new URL(request.url).pathname;
  const functionMarker = pathname.indexOf('/functions/v1/');
  if (functionMarker >= 0) {
    const functionPath = pathname.slice(functionMarker + '/functions/v1/'.length);
    const separator = functionPath.indexOf('/');
    return separator >= 0 ? functionPath.slice(separator) || '/' : '/';
  }
  if (/^\/(?:platform-api|platform-public|platform-admin)\/?$/.test(pathname)) return '/';
  const marker = pathname.lastIndexOf('/v1/');
  return marker >= 0 ? pathname.slice(marker) : pathname;
}

export async function parseJsonObject(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const value: unknown = await request.json();
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}
