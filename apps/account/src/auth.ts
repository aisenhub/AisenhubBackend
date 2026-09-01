export type AccountAuthSession = {
  readonly accessToken: string;
};

type AuthClientOptions = {
  readonly supabaseUrl: string;
  readonly anonKey: string;
  readonly fetchImplementation?: typeof globalThis.fetch;
};

export class AccountAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AccountAuthError';
  }
}

export class AccountAuthClient {
  private readonly supabaseUrl: string;
  private readonly anonKey: string;
  private readonly requestFetch: typeof globalThis.fetch;
  private session: AccountAuthSession | null = null;

  constructor(options: AuthClientOptions) {
    this.supabaseUrl = options.supabaseUrl.replace(/\/$/, '');
    this.anonKey = options.anonKey;
    this.requestFetch = options.fetchImplementation ?? globalThis.fetch;
  }

  get accessToken(): string | null {
    return this.session?.accessToken ?? null;
  }

  async signInWithPassword(email: string, password: string): Promise<AccountAuthSession> {
    return this.tokenRequest('password', { email, password });
  }

  async exchangePkceCode(code: string, codeVerifier: string): Promise<AccountAuthSession> {
    return this.tokenRequest('pkce', { auth_code: code, code_verifier: codeVerifier });
  }

  signOut(): void {
    this.session = null;
  }

  private async tokenRequest(
    grantType: 'password' | 'pkce',
    body: Record<string, string>,
  ): Promise<AccountAuthSession> {
    if (this.anonKey.trim() === '') throw new AccountAuthError('Account Auth is not configured.');

    const response = await this.requestFetch(
      `${this.supabaseUrl}/auth/v1/token?grant_type=${grantType}`,
      {
        method: 'POST',
        headers: { apikey: this.anonKey, 'content-type': 'application/json' },
        body: JSON.stringify(body),
      },
    );
    const payload: unknown = await response.json().catch(() => null);
    if (!response.ok || !payload || typeof payload !== 'object' || !('access_token' in payload)) {
      throw new AccountAuthError('We could not sign you in with those details.');
    }

    const accessToken = payload.access_token;
    if (typeof accessToken !== 'string' || accessToken === '') {
      throw new AccountAuthError('The sign-in response was invalid.');
    }

    this.session = { accessToken };
    return this.session;
  }
}
