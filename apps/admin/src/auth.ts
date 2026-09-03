import {
  createOAuthClient,
  type OAuthAuthorizationStart,
  type OAuthStorage,
} from '@aisenhub/auth-client';

export type AdminAuthSession = {
  readonly accessToken: string;
  readonly refreshToken: string | null;
};

type AdminAuthClientOptions = {
  readonly supabaseUrl: string;
  readonly clientId: string;
  readonly redirectUri: string;
  readonly storage?: OAuthStorage;
  readonly fetchImplementation?: typeof globalThis.fetch;
};

export class AdminAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AdminAuthError';
  }
}

export class AdminAuthClient {
  private readonly oauthClient: ReturnType<typeof createOAuthClient>;
  private readonly sessionStorage: OAuthStorage;
  private session: AdminAuthSession | null = null;

  constructor(options: AdminAuthClientOptions) {
    const supabaseUrl = options.supabaseUrl.replace(/\/$/, '');
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
      storagePrefix: 'aisenhub.admin.oauth',
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

  async completeAuthorization(callbackUrl: string | URL): Promise<AdminAuthSession> {
    let callback;
    try {
      callback = this.oauthClient.readCallback(callbackUrl);
    } catch {
      throw new AdminAuthError('We could not validate the secure Admin sign-in callback.');
    }
    let response;
    try {
      response = await this.oauthClient.exchangeCode(callback);
    } catch {
      throw new AdminAuthError('We could not complete secure Admin sign-in.');
    }
    this.session = {
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    };
    this.persistSession();
    return this.session;
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
}
