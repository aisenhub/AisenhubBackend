import { healthResponse } from './health.ts';
import {
  apiPath,
  errorResponse,
  jsonResponse,
  preflightResponse,
  requestId,
  resolveOrigin,
  rpc,
  withCors,
} from './platform-api.ts';

type PublicAppRow = {
  readonly slug: string;
  readonly name: string;
  readonly category: string;
  readonly status: 'active';
};

type PublicProductRow = {
  readonly sku: string;
  readonly name: string;
  readonly billing_type: 'one_time' | 'subscription' | 'credits';
  readonly version: number;
};

function isPublicApp(value: unknown): value is PublicAppRow {
  if (!value || typeof value !== 'object') return false;
  const row = value as Record<string, unknown>;
  return (
    typeof row.slug === 'string' &&
    typeof row.name === 'string' &&
    typeof row.category === 'string' &&
    row.status === 'active'
  );
}

function isPublicProduct(value: unknown): value is PublicProductRow {
  if (!value || typeof value !== 'object') return false;
  const row = value as Record<string, unknown>;
  return (
    typeof row.sku === 'string' &&
    typeof row.name === 'string' &&
    ['one_time', 'subscription', 'credits'].includes(String(row.billing_type)) &&
    typeof row.version === 'number' &&
    Number.isInteger(row.version) &&
    row.version > 0
  );
}

async function appRead(slug: string, id: string): Promise<Response> {
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) {
    return errorResponse('APP_NOT_FOUND', 'Application was not found.', 404, id);
  }

  try {
    const rows = await rpc<PublicAppRow>('get_public_app', { app_slug: slug });
    const app = rows.length === 1 && isPublicApp(rows[0]) ? rows[0] : null;
    return app
      ? jsonResponse({ app }, 200, id)
      : errorResponse('APP_NOT_FOUND', 'Application was not found.', 404, id);
  } catch {
    return errorResponse('INTERNAL_ERROR', 'The application could not be read.', 502, id);
  }
}

async function productsRead(id: string): Promise<Response> {
  try {
    const rows = await rpc<PublicProductRow>('get_public_products', {});
    if (!rows.every(isPublicProduct)) {
      return errorResponse('INTERNAL_ERROR', 'The public catalog could not be read.', 502, id);
    }
    return jsonResponse(
      {
        products: rows.map((row) => ({
          sku: row.sku,
          name: row.name,
          billingType: row.billing_type,
          version: row.version,
        })),
      },
      200,
      id,
    );
  } catch {
    return errorResponse('INTERNAL_ERROR', 'The public catalog could not be read.', 502, id);
  }
}

async function routePublic(request: Request, id: string): Promise<Response> {
  const path = apiPath(request);
  if (path === '/' || path === '') return healthResponse('platform-public');
  if (request.method !== 'GET') {
    return errorResponse('VALIDATION_ERROR', 'Only GET requests are supported.', 405, id);
  }
  if (path.startsWith('/v1/apps/')) {
    return appRead(decodeURIComponent(path.slice('/v1/apps/'.length)), id);
  }
  if (path === '/v1/products/public') return productsRead(id);
  return errorResponse('VALIDATION_ERROR', 'The requested route was not found.', 404, id);
}

export async function routePlatformPublic(request: Request): Promise<Response> {
  const id = requestId();
  const resolved = await resolveOrigin(request, id);
  if (resolved instanceof Response) return resolved;
  if (request.method === 'OPTIONS') {
    return resolved
      ? preflightResponse(request, id, resolved)
      : errorResponse('ORIGIN_NOT_ALLOWED', 'A request Origin is required.', 403, id);
  }
  return withCors(await routePublic(request, id), resolved);
}
