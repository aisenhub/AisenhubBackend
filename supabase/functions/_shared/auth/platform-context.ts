import {
  createApplicationContextKernel,
  type ApplicationContextKernel,
} from './application-context.ts';
import { createAccessTokenVerifier } from './token-verifier.ts';

type RpcValue = unknown[] | Record<string, unknown>;

const apiUrl = () => Deno.env.get('SUPABASE_URL') ?? 'http://127.0.0.1:54321';

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

async function rpc(name: string, body: Record<string, unknown>, key: string): Promise<unknown> {
  const response = await fetch(`${apiUrl()}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error('The application context data operation failed.');
  const value: unknown = await response.json();
  if (Array.isArray(value) || (value && typeof value === 'object')) return value as RpcValue;
  throw new Error('The application context data operation returned an invalid shape.');
}

export function createPlatformApplicationContextKernel(): ApplicationContextKernel {
  const serviceRoleKey = requiredEnv('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey = requiredEnv('SUPABASE_ANON_KEY');
  const baseUrl = apiUrl().replace(/\/$/, '');
  const verifyAccessToken = createAccessTokenVerifier({
    issuer: Deno.env.get('SUPABASE_AUTH_ISSUER')?.trim() || `${baseUrl}/auth/v1`,
    jwksUrl:
      Deno.env.get('SUPABASE_AUTH_JWKS_URL')?.trim() || `${baseUrl}/auth/v1/.well-known/jwks.json`,
  });

  return createApplicationContextKernel({
    verifyAccessToken,
    resolveContext: async (userId, clientId) =>
      rpc(
        'resolve_application_context',
        { p_user_id: userId, p_client_id: clientId },
        serviceRoleKey,
      ),
    resolveOrigin: async (origin) => {
      const value = await rpc('resolve_app_origin', { p_origin: origin }, anonKey);
      const rows = Array.isArray(value) ? value : [value];
      if (rows.length !== 1 || !rows[0] || typeof rows[0] !== 'object') return null;
      const slug = (rows[0] as Record<string, unknown>).app_slug;
      return typeof slug === 'string' ? slug : null;
    },
  });
}
