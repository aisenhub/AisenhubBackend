export interface TestHttpResponse<T> {
  readonly status: number;
  readonly requestId: string | null;
  readonly body: T | null;
  readonly cookies: readonly string[];
}

export interface TestHttpClientOptions {
  readonly fetchImplementation?: typeof fetch;
  readonly csrfToken?: string;
}

type ResponseHeadersWithCookies = Headers & {
  getSetCookie?: () => string[];
};

export class TestHttpClient {
  private readonly baseUrl: URL;
  private readonly fetchImplementation: typeof fetch;
  private readonly csrfToken: string | undefined;
  private readonly cookieJar = new Map<string, string>();

  public constructor(baseUrl: string | URL, options: TestHttpClientOptions = {}) {
    this.baseUrl = new URL(baseUrl);
    this.fetchImplementation = options.fetchImplementation ?? fetch;
    this.csrfToken = options.csrfToken;
  }

  public async request<T>(path: string, init: RequestInit = {}): Promise<TestHttpResponse<T>> {
    const headers = new Headers(init.headers);
    const cookie = this.serializeCookies();
    if (cookie !== '') {
      headers.set('cookie', cookie);
    }
    if (this.csrfToken !== undefined) {
      headers.set('x-csrf-token', this.csrfToken);
    }

    const response = await this.fetchImplementation(new URL(path, this.baseUrl), {
      ...init,
      credentials: 'include',
      headers,
    });
    this.captureCookies(response.headers);

    const body = await this.parseBody<T>(response);
    return {
      status: response.status,
      requestId: response.headers.get('x-request-id'),
      body,
      cookies: [...this.cookieJar.values()],
    };
  }

  private async parseBody<T>(response: Response): Promise<T | null> {
    const contentType = response.headers.get('content-type') ?? '';
    if (!contentType.includes('application/json')) {
      return null;
    }
    return (await response.json()) as T;
  }

  private captureCookies(headers: Headers): void {
    const cookieHeaders = (headers as ResponseHeadersWithCookies).getSetCookie?.() ?? [];
    for (const cookieHeader of cookieHeaders) {
      const [nameValue] = cookieHeader.split(';', 1);
      const separator = nameValue.indexOf('=');
      if (separator > 0) {
        this.cookieJar.set(nameValue.slice(0, separator), nameValue.slice(separator + 1));
      }
    }
  }

  private serializeCookies(): string {
    return [...this.cookieJar.entries()].map(([name, value]) => `${name}=${value}`).join('; ');
  }
}
