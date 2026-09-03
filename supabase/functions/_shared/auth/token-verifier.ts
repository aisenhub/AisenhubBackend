export type PlatformJsonWebKey = JsonWebKey & {
  readonly kid?: string;
  readonly alg?: string;
  readonly use?: string;
  readonly key_ops?: readonly string[];
};

export type JsonWebKeySet = {
  readonly keys?: readonly PlatformJsonWebKey[];
};

export type VerifiedAccessToken = {
  readonly userId: string;
  readonly issuer: string;
  readonly audience: string;
  readonly expiresAt: number;
  readonly issuedAt: number | null;
  readonly clientId: string;
  readonly role: string;
  readonly aal: string | null;
};

export type AccessTokenVerifierOptions = {
  readonly jwksUrl: string;
  readonly issuer: string;
  readonly audience?: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly cacheTtlMs?: number;
  readonly clockSkewSeconds?: number;
};

export class AccessTokenVerificationError extends Error {
  constructor(message = 'Access token verification failed.') {
    super(message);
    this.name = 'AccessTokenVerificationError';
  }
}

type JwtHeader = {
  readonly alg?: unknown;
  readonly kid?: unknown;
  readonly typ?: unknown;
};

type JwtPayload = {
  readonly iss?: unknown;
  readonly sub?: unknown;
  readonly aud?: unknown;
  readonly exp?: unknown;
  readonly iat?: unknown;
  readonly nbf?: unknown;
  readonly client_id?: unknown;
  readonly role?: unknown;
  readonly aal?: unknown;
};

const allowedAlgorithms = new Map<string, AlgorithmIdentifier>([
  ['RS256', 'RSASSA-PKCS1-v1_5'],
  ['ES256', 'ECDSA'],
]);

function decodeBase64Url(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]*$/.test(value)) throw new AccessTokenVerificationError();
  const padded =
    value.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - (value.length % 4)) % 4);
  try {
    return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
  } catch {
    throw new AccessTokenVerificationError();
  }
}

function parseJsonSegment<T>(segment: string): T {
  try {
    const parsed: unknown = JSON.parse(new TextDecoder().decode(decodeBase64Url(segment)));
    if (!parsed || typeof parsed !== 'object') throw new Error('not an object');
    return parsed as T;
  } catch {
    throw new AccessTokenVerificationError();
  }
}

function isAudience(payload: JwtPayload, expected: string): boolean {
  if (typeof payload.aud === 'string') return payload.aud === expected;
  return (
    Array.isArray(payload.aud) &&
    payload.aud.length > 0 &&
    payload.aud.every((value) => typeof value === 'string') &&
    payload.aud.includes(expected)
  );
}

function requiredString(value: unknown): string {
  if (typeof value !== 'string' || value.trim() === '') throw new AccessTokenVerificationError();
  return value;
}

function requiredTimestamp(value: unknown): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
    throw new AccessTokenVerificationError();
  }
  return value;
}

function validateJwk(jwk: PlatformJsonWebKey, algorithm: string, kid: string): void {
  if (jwk.kid !== kid || (jwk.use !== undefined && jwk.use !== 'sig')) {
    throw new AccessTokenVerificationError();
  }
  if (jwk.key_ops !== undefined && !jwk.key_ops.includes('verify')) {
    throw new AccessTokenVerificationError();
  }
  if (algorithm === 'RS256' && jwk.kty !== 'RSA') throw new AccessTokenVerificationError();
  if (algorithm === 'ES256' && (jwk.kty !== 'EC' || jwk.crv !== 'P-256')) {
    throw new AccessTokenVerificationError();
  }
  if (jwk.alg !== undefined && jwk.alg !== algorithm) throw new AccessTokenVerificationError();
}

export function createAccessTokenVerifier(options: AccessTokenVerifierOptions) {
  const requestFetch = options.fetch ?? globalThis.fetch.bind(globalThis);
  const now = options.now ?? (() => Date.now());
  const audience = options.audience ?? 'authenticated';
  const cacheTtlMs = options.cacheTtlMs ?? 5 * 60 * 1000;
  const clockSkewSeconds = options.clockSkewSeconds ?? 30;
  let cachedJwks: JsonWebKeySet | null = null;
  let cachedAt = 0;

  return async function verifyAccessToken(token: string): Promise<VerifiedAccessToken> {
    const segments = token.split('.');
    if (segments.length !== 3 || token.length > 16_384) throw new AccessTokenVerificationError();
    const header = parseJsonSegment<JwtHeader>(segments[0]);
    const payload = parseJsonSegment<JwtPayload>(segments[1]);
    const algorithm = requiredString(header.alg);
    const keyId = requiredString(header.kid);
    if (!allowedAlgorithms.has(algorithm) || (header.typ !== undefined && header.typ !== 'JWT')) {
      throw new AccessTokenVerificationError();
    }

    const headerBytes = new TextEncoder().encode(`${segments[0]}.${segments[1]}`);
    const signature = decodeBase64Url(segments[2]);
    const jwks = await getJwks();
    const jwk = jwks.keys?.find((key) => key.kid === keyId);
    if (!jwk) throw new AccessTokenVerificationError();
    validateJwk(jwk, algorithm, keyId);

    const keyAlgorithm =
      algorithm === 'RS256'
        ? { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }
        : { name: 'ECDSA', namedCurve: 'P-256' };
    const verifyAlgorithm =
      algorithm === 'RS256' ? { name: 'RSASSA-PKCS1-v1_5' } : { name: 'ECDSA', hash: 'SHA-256' };
    let key: CryptoKey;
    try {
      key = await crypto.subtle.importKey('jwk', jwk, keyAlgorithm, false, ['verify']);
      if (
        !(await crypto.subtle.verify(
          verifyAlgorithm,
          key,
          signature as unknown as BufferSource,
          headerBytes,
        ))
      ) {
        throw new AccessTokenVerificationError();
      }
    } catch {
      throw new AccessTokenVerificationError();
    }

    const issuer = requiredString(payload.iss);
    const userId = requiredString(payload.sub);
    if (
      issuer !== options.issuer ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)
    ) {
      throw new AccessTokenVerificationError();
    }
    if (!isAudience(payload, audience)) throw new AccessTokenVerificationError();
    const expiresAt = requiredTimestamp(payload.exp);
    const currentSeconds = Math.floor(now() / 1000);
    if (expiresAt <= currentSeconds - clockSkewSeconds) throw new AccessTokenVerificationError();
    if (
      payload.nbf !== undefined &&
      requiredTimestamp(payload.nbf) > currentSeconds + clockSkewSeconds
    ) {
      throw new AccessTokenVerificationError();
    }
    const role = requiredString(payload.role);
    if (role !== 'authenticated') throw new AccessTokenVerificationError();

    return {
      userId,
      issuer,
      audience,
      expiresAt,
      issuedAt: payload.iat === undefined ? null : requiredTimestamp(payload.iat),
      clientId: requiredString(payload.client_id),
      role,
      aal: payload.aal === undefined ? null : requiredString(payload.aal),
    };
  };

  async function getJwks(): Promise<JsonWebKeySet> {
    if (cachedJwks && now() - cachedAt < cacheTtlMs) return cachedJwks;
    const response = await requestFetch(options.jwksUrl, {
      headers: { accept: 'application/json' },
    }).catch(() => null);
    if (!response?.ok) throw new AccessTokenVerificationError();
    const payload: unknown = await response.json().catch(() => null);
    if (
      !payload ||
      typeof payload !== 'object' ||
      !Array.isArray((payload as JsonWebKeySet).keys)
    ) {
      throw new AccessTokenVerificationError();
    }
    cachedJwks = payload as JsonWebKeySet;
    cachedAt = now();
    return cachedJwks;
  }
}
