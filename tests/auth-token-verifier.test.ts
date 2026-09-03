import { describe, expect, it } from 'vitest';

import {
  AccessTokenVerificationError,
  createAccessTokenVerifier,
} from '../supabase/functions/_shared/auth/token-verifier';

const userId = '00000000-0000-4000-8000-000000000001';
const issuer = 'https://auth.example.test/auth/v1';

function encode(value: unknown): string {
  return btoa(JSON.stringify(value)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

describe('access token verifier', () => {
  it('verifies an asymmetric RS256 JWT and caches the JWKS', async () => {
    const keyPair = await crypto.subtle.generateKey(
      {
        name: 'RSASSA-PKCS1-v1_5',
        modulusLength: 2048,
        publicExponent: new Uint8Array([1, 0, 1]),
        hash: 'SHA-256',
      },
      true,
      ['sign', 'verify'],
    );
    const publicJwk = Object.assign(await crypto.subtle.exportKey('jwk', keyPair.publicKey), {
      kid: 'key-a',
      alg: 'RS256',
      use: 'sig',
    });
    let jwksCalls = 0;
    const now = () => 1_800_000_000_000;
    const verifier = createAccessTokenVerifier({
      jwksUrl: 'https://auth.example.test/jwks',
      issuer,
      now,
      fetch: async () => {
        jwksCalls += 1;
        return new Response(JSON.stringify({ keys: [publicJwk] }), { status: 200 });
      },
    });
    const header = encode({ alg: 'RS256', kid: 'key-a', typ: 'JWT' });
    const payload = encode({
      iss: issuer,
      sub: userId,
      aud: 'authenticated',
      exp: 1_800_000_600,
      iat: 1_800_000_000,
      client_id: 'client-a',
      role: 'authenticated',
      aal: 'aal1',
    });
    const signingInput = new TextEncoder().encode(`${header}.${payload}`);
    const signature = await crypto.subtle.sign(
      { name: 'RSASSA-PKCS1-v1_5' },
      keyPair.privateKey,
      signingInput,
    );
    const token = `${header}.${payload}.${btoa(String.fromCharCode(...new Uint8Array(signature)))
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll('=', '')}`;

    await expect(verifier(token)).resolves.toMatchObject({
      userId,
      clientId: 'client-a',
      role: 'authenticated',
    });
    await expect(verifier(token)).resolves.toMatchObject({ userId });
    expect(jwksCalls).toBe(1);
  });

  it('denies wrong issuer, audience, role, client absence and expired tokens', async () => {
    const verifier = createAccessTokenVerifier({
      jwksUrl: 'https://auth.example.test/jwks',
      issuer,
      now: () => 1_800_000_000_000,
      fetch: async () => new Response(JSON.stringify({ keys: [] }), { status: 200 }),
    });
    for (const payload of [
      {
        iss: 'https://wrong.example.test',
        aud: 'authenticated',
        exp: 1_800_000_600,
        role: 'authenticated',
        client_id: 'client-a',
      },
      {
        iss: issuer,
        aud: 'another-api',
        exp: 1_800_000_600,
        role: 'authenticated',
        client_id: 'client-a',
      },
      {
        iss: issuer,
        aud: 'authenticated',
        exp: 1_800_000_600,
        role: 'service_role',
        client_id: 'client-a',
      },
      {
        iss: issuer,
        aud: 'authenticated',
        exp: 1_799_999_900,
        role: 'authenticated',
        client_id: 'client-a',
      },
    ]) {
      const token = `${encode({ alg: 'none', kid: 'missing' })}.${encode({ ...payload, sub: userId })}.invalid`;
      await expect(verifier(token)).rejects.toBeInstanceOf(AccessTokenVerificationError);
    }
  });
});
