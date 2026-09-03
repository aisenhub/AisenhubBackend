const apiUrl = () => Deno.env.get('SUPABASE_URL') ?? 'http://127.0.0.1:54321';
const anonKey = () => Deno.env.get('SUPABASE_ANON_KEY');
const serviceRoleKey = () => Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

export async function rpc<T>(
  name: string,
  body: Record<string, unknown>,
  token?: string,
): Promise<T[]> {
  const key = anonKey();
  if (!key) throw new Error('Supabase anon key is not configured.');

  const headers = new Headers({
    apikey: key,
    'content-type': 'application/json',
    accept: 'application/json',
  });
  if (token) headers.set('authorization', `Bearer ${token}`);

  const response = await fetch(`${apiUrl()}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error('Supabase read entry failed.');

  const value: unknown = await response.json();
  if (Array.isArray(value)) return value as T[];
  if (value && typeof value === 'object') return [value as T];
  throw new Error('Supabase read entry returned an invalid shape.');
}

export class ServiceRpcError extends Error {
  readonly databaseCode: string | undefined;

  constructor(databaseCode?: string) {
    super('The server data operation failed.');
    this.name = 'ServiceRpcError';
    this.databaseCode = databaseCode;
  }
}

export async function serviceRpc<T>(name: string, body: Record<string, unknown>): Promise<T[]> {
  const key = serviceRoleKey();
  if (!key) throw new Error('Supabase service role key is not configured.');

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
  if (!response.ok) {
    let databaseCode: string | undefined;
    try {
      const payload: unknown = await response.json();
      if (payload && typeof payload === 'object' && 'code' in payload) {
        databaseCode = typeof payload.code === 'string' ? payload.code : undefined;
      }
    } catch {
      // Deliberately discard upstream error details.
    }
    throw new ServiceRpcError(databaseCode);
  }

  const value: unknown = await response.json();
  if (Array.isArray(value)) return value as T[];
  if (value && typeof value === 'object') return [value as T];
  throw new Error('The server data operation returned an invalid shape.');
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
