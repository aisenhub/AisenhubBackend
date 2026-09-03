import {
  createOAuthClient,
  type OAuthAuthorizationStart,
  type OAuthStorage,
} from '@aisenhub/auth-client';

export type AccountAuthSession = {
  readonly accessToken: string;
  readonly refreshToken: string | null;
};

type AuthClientOptions = {
  readonly supabaseUrl: string;
  readonly clientId: string;
  readonly redirectUri: string;
  readonly supabaseAnonKey?: string;
  readonly storage?: OAuthStorage;
  readonly fetchImplementation?: typeof globalThis.fetch;
};

export type OAuthAuthorizationDetails = {
  readonly authorizationId: string;
  readonly redirectUri: string;
  readonly client: {
    readonly id: string;
    readonly name: string;
    readonly uri: string | null;
    readonly logoUri: string | null;
  };
  readonly scope: string;
  readonly user: { readonly id: string; readonly email: string | null };
};

export class AccountAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AccountAuthError';
  }
}

export class AccountAuthClient {
  private readonly oauthClient: ReturnType<typeof createOAuthClient>;
  private readonly sessionStorage: OAuthStorage;
  private readonly supabaseUrl: string;
  private readonly supabaseAnonKey: string | null;
  private readonly requestFetch: typeof globalThis.fetch;
  private session: AccountAuthSession | null = null;

  constructor(options: AuthClientOptions) {
    const supabaseUrl = options.supabaseUrl.replace(/\/$/, '');
    this.supabaseUrl = supabaseUrl;
    this.supabaseAnonKey = options.supabaseAnonKey?.trim() || null;
    this.requestFetch = options.fetchImplementation ?? globalThis.fetch.bind(globalThis);
    this.sessionStorage = options.storage ?? {
      getItem: (key) => globalThis.sessionStorage?.getItem(key) ?? null,
      setItem: (key, value) => globalThis.sessionStorage?.setItem(key, value),
      removeItem: (key) => globalThis.sessionStorage?.removeItem(key),
    };
    this.oauthClient = createOAuthClient({
      authorizationEndpoint: `${supabaseUrl}/auth/v1/oauth/authorize`,
      tokenEndpoint: `${supabaseUrl}/auth/v1/oauth/token`,
      clientId: options.clientId,
      redirectUri: options.redirectUri,
      storage: options.storage,
      fetch: options.fetchImplementation,
      storagePrefix: 'aisenhub.account.oauth',
    });
    const accessToken = this.sessionStorage.getItem('aisenhub.access_token');
    const refreshToken = this.sessionStorage.getItem('aisenhub.refresh_token');
    if (accessToken) this.session = { accessToken, refreshToken };
  }

  get accessToken(): string | null {
    return this.session?.accessToken ?? null;
  }

  async startAuthorization(): Promise<OAuthAuthorizationStart> {
    return this.oauthClient.startAuthorization();
  }

  async completeAuthorization(callbackUrl: string | URL): Promise<AccountAuthSession> {
    const callback = this.oauthClient.readCallback(callbackUrl);
    let response;
    try {
      response = await this.oauthClient.exchangeCode(callback);
    } catch {
      throw new AccountAuthError('We could not complete secure sign-in.');
    }
    this.session = {
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    };
    this.persistSession();
    return this.session;
  }

  async getAuthorizationDetails(authorizationId: string): Promise<OAuthAuthorizationDetails> {
    const data = await this.requestAuthorization(authorizationId, 'GET');
    if (!isAuthorizationDetails(data)) {
      throw new AccountAuthError('This authorization request is no longer available.');
    }
    return normalizeAuthorizationDetails(data);
  }

  async approveAuthorization(authorizationId: string): Promise<string> {
    return this.decideAuthorization(authorizationId, 'approve');
  }

  async denyAuthorization(authorizationId: string): Promise<string> {
    return this.decideAuthorization(authorizationId, 'deny');
  }

  signOut(): void {
    this.session = null;
    this.sessionStorage.removeItem('aisenhub.access_token');
    this.sessionStorage.removeItem('aisenhub.refresh_token');
  }

  private persistSession(): void {
    this.sessionStorage.setItem('aisenhub.access_token', this.session?.accessToken ?? '');
    if (this.session?.refreshToken) {
      this.sessionStorage.setItem('aisenhub.refresh_token', this.session.refreshToken);
    } else {
      this.sessionStorage.removeItem('aisenhub.refresh_token');
    }
  }

  private async decideAuthorization(
    authorizationId: string,
    action: 'approve' | 'deny',
  ): Promise<string> {
    const data = await this.requestAuthorization(authorizationId, 'POST', { action });
    if (!isRedirectResponse(data)) {
      throw new AccountAuthError('The authorization decision could not be completed.');
    }
    return data.redirect_url;
  }

  private async requestAuthorization(
    authorizationId: string,
    method: 'GET' | 'POST',
    body?: { readonly action: 'approve' | 'deny' },
  ): Promise<unknown> {
    if (!this.session?.accessToken) {
      throw new AccountAuthError('Please sign in before authorizing an application.');
    }
    if (!/^[A-Za-z0-9_-]+$/.test(authorizationId)) {
      throw new AccountAuthError('This authorization request is invalid.');
    }
    const headers = new Headers({
      Accept: 'application/json',
      Authorization: `Bearer ${this.session.accessToken}`,
      ...(this.supabaseAnonKey ? { apikey: this.supabaseAnonKey } : {}),
    });
    if (body) headers.set('content-type', 'application/json');
    let response: Response;
    try {
      response = await this.requestFetch(
        `${this.supabaseUrl}/auth/v1/oauth/authorizations/${authorizationId}${
          method === 'POST' ? '/consent' : ''
        }`,
        { method, headers, body: body ? JSON.stringify(body) : undefined },
      );
    } catch {
      throw new AccountAuthError('The authorization service is unavailable.');
    }
    let responseBody: unknown;
    try {
      responseBody = await response.json();
    } catch {
      throw new AccountAuthError('The authorization service returned an invalid response.');
    }
    if (!response.ok) throw new AccountAuthError('The authorization request could not be loaded.');
    return responseBody;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function isAuthorizationDetails(value: unknown): value is Record<string, unknown> {
  return (
    isRecord(value) &&
    typeof value.authorization_id === 'string' &&
    isRecord(value.client) &&
    typeof value.client.id === 'string' &&
    typeof value.client.name === 'string' &&
    typeof value.redirect_uri === 'string' &&
    typeof value.scope === 'string' &&
    isRecord(value.user) &&
    typeof value.user.id === 'string'
  );
}

function normalizeAuthorizationDetails(value: Record<string, unknown>): OAuthAuthorizationDetails {
  const client = value.client as Record<string, unknown>;
  const user = value.user as Record<string, unknown>;
  return {
    authorizationId: value.authorization_id as string,
    redirectUri: value.redirect_uri as string,
    client: {
      id: client.id as string,
      name: client.name as string,
      uri: typeof client.uri === 'string' ? client.uri : null,
      logoUri: typeof client.logo_uri === 'string' ? client.logo_uri : null,
    },
    scope: value.scope as string,
    user: {
      id: user.id as string,
      email: typeof user.email === 'string' ? user.email : null,
    },
  };
}

function isRedirectResponse(value: unknown): value is { readonly redirect_url: string } {
  if (!isRecord(value) || typeof value.redirect_url !== 'string') return false;
  try {
    return ['http:', 'https:'].includes(new URL(value.redirect_url).protocol);
  } catch {
    return false;
  }
}
