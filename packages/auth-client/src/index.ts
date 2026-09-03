export type OAuthStorage = {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
};

export type OAuthClientOptions = {
  readonly authorizationEndpoint: string;
  readonly tokenEndpoint: string;
  readonly clientId: string;
  readonly redirectUri: string;
  readonly scope?: string;
  readonly storage?: OAuthStorage;
  readonly storagePrefix?: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
};

export type OAuthAuthorizationStart = {
  readonly authorizationUrl: string;
  readonly state: string;
  readonly nonce: string;
  readonly codeVerifier: string;
};

export type OAuthCallback = {
  readonly code: string;
  readonly state: string;
  readonly nonce: string;
  readonly codeVerifier: string;
};

export type OAuthTokenResponse = {
  readonly accessToken: string;
  readonly refreshToken: string | null;
  readonly idToken: string | null;
  readonly tokenType: string;
  readonly expiresIn: number | null;
};

export class OAuthClientError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OAuthClientError';
  }
}

const defaultStorage: OAuthStorage = {
  getItem: (key) => globalThis.sessionStorage?.getItem(key) ?? null,
  setItem: (key, value) => globalThis.sessionStorage?.setItem(key, value),
  removeItem: (key) => globalThis.sessionStorage?.removeItem(key),
};

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function randomValue(byteLength = 32): string {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return encodeBase64Url(bytes);
}

async function sha256Base64Url(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return encodeBase64Url(new Uint8Array(digest));
}

function equalSecret(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export class OAuthClient {
  private readonly authorizationEndpoint: string;
  private readonly tokenEndpoint: string;
  private readonly clientId: string;
  private readonly redirectUri: string;
  private readonly scope: string;
  private readonly storage: OAuthStorage;
  private readonly storagePrefix: string;
  private readonly requestFetch: typeof globalThis.fetch;
  private readonly now: () => number;

  constructor(options: OAuthClientOptions) {
    if (!options.clientId.trim() || !options.redirectUri.trim()) {
      throw new OAuthClientError('OAuth client id and redirect URI are required.');
    }
    this.authorizationEndpoint = new URL(options.authorizationEndpoint).toString();
    this.tokenEndpoint = new URL(options.tokenEndpoint).toString();
    this.clientId = options.clientId;
    this.redirectUri = options.redirectUri;
    this.scope = options.scope?.trim() || 'openid email profile';
    this.storage = options.storage ?? defaultStorage;
    this.storagePrefix = options.storagePrefix ?? 'aisenhub.oauth';
    this.requestFetch = options.fetch ?? globalThis.fetch.bind(globalThis);
    this.now = options.now ?? Date.now;
  }

  async startAuthorization(): Promise<OAuthAuthorizationStart> {
    const state = randomValue();
    const nonce = randomValue();
    const codeVerifier = randomValue(48);
    const codeChallenge = await sha256Base64Url(codeVerifier);
    const transaction = JSON.stringify({ state, nonce, codeVerifier, createdAt: this.now() });
    this.storage.setItem(`${this.storagePrefix}.${state}`, transaction);

    const authorizationUrl = new URL(this.authorizationEndpoint);
    authorizationUrl.searchParams.set('response_type', 'code');
    authorizationUrl.searchParams.set('client_id', this.clientId);
    authorizationUrl.searchParams.set('redirect_uri', this.redirectUri);
    authorizationUrl.searchParams.set('scope', this.scope);
    authorizationUrl.searchParams.set('state', state);
    authorizationUrl.searchParams.set('nonce', nonce);
    authorizationUrl.searchParams.set('code_challenge', codeChallenge);
    authorizationUrl.searchParams.set('code_challenge_method', 'S256');

    return { authorizationUrl: authorizationUrl.toString(), state, nonce, codeVerifier };
  }

  readCallback(callbackUrl: string | URL): OAuthCallback {
    const url = new URL(callbackUrl.toString());
    const state = url.searchParams.get('state') ?? '';
    const error = url.searchParams.get('error');
    if (error) throw new OAuthClientError(`OAuth authorization failed: ${error}.`);
    const code = url.searchParams.get('code') ?? '';
    if (!state || !code) throw new OAuthClientError('OAuth callback is missing code or state.');

    const storageKey = `${this.storagePrefix}.${state}`;
    const raw = this.storage.getItem(storageKey);
    this.storage.removeItem(storageKey);
    if (!raw) throw new OAuthClientError('OAuth callback state is missing or expired.');

    let transaction: unknown;
    try {
      transaction = JSON.parse(raw);
    } catch {
      throw new OAuthClientError('OAuth callback state is invalid.');
    }
    if (!transaction || typeof transaction !== 'object') {
      throw new OAuthClientError('OAuth callback state is invalid.');
    }
    const stored = transaction as Record<string, unknown>;
    if (
      typeof stored.state !== 'string' ||
      typeof stored.nonce !== 'string' ||
      typeof stored.codeVerifier !== 'string' ||
      typeof stored.createdAt !== 'number' ||
      !equalSecret(stored.state, state) ||
      this.now() - stored.createdAt > 10 * 60 * 1000
    ) {
      throw new OAuthClientError('OAuth callback state is invalid or expired.');
    }
    return { code, state, nonce: stored.nonce, codeVerifier: stored.codeVerifier };
  }

  async exchangeCode(callback: OAuthCallback): Promise<OAuthTokenResponse> {
    return this.tokenRequest({
      grant_type: 'authorization_code',
      code: callback.code,
      client_id: this.clientId,
      redirect_uri: this.redirectUri,
      code_verifier: callback.codeVerifier,
    });
  }

  async refresh(refreshToken: string): Promise<OAuthTokenResponse> {
    const normalizedToken = refreshToken.trim();
    if (!normalizedToken) throw new OAuthClientError('A refresh token is required.');
    return this.tokenRequest({
      grant_type: 'refresh_token',
      refresh_token: normalizedToken,
      client_id: this.clientId,
    });
  }

  private async tokenRequest(body: Record<string, string>): Promise<OAuthTokenResponse> {
    const response = await this.requestFetch(this.tokenEndpoint, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded', accept: 'application/json' },
      body: new URLSearchParams(body).toString(),
    });
    const payload: unknown = await response.json().catch(() => null);
    if (!response.ok || !payload || typeof payload !== 'object') {
      throw new OAuthClientError('The OAuth token exchange failed.');
    }
    const record = payload as Record<string, unknown>;
    if (typeof record.access_token !== 'string' || record.access_token === '') {
      throw new OAuthClientError('The OAuth token response is invalid.');
    }
    return {
      accessToken: record.access_token,
      refreshToken: typeof record.refresh_token === 'string' ? record.refresh_token : null,
      idToken: typeof record.id_token === 'string' ? record.id_token : null,
      tokenType: typeof record.token_type === 'string' ? record.token_type : 'Bearer',
      expiresIn: typeof record.expires_in === 'number' ? record.expires_in : null,
    };
  }
}

export function createOAuthClient(options: OAuthClientOptions): OAuthClient {
  return new OAuthClient(options);
}
