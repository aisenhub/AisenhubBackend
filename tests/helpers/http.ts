export interface TestHttpResponse<T> {
  readonly status: number;
  readonly requestId: string | null;
  readonly body: T | null;
}

export interface TestHttpClientOptions {
  readonly fetchImplementation?: typeof fetch;
}

export class TestHttpClient {
  private readonly baseUrl: URL;
  private readonly fetchImplementation: typeof fetch;

  public constructor(baseUrl: string | URL, options: TestHttpClientOptions = {}) {
    this.baseUrl = new URL(baseUrl);
    this.fetchImplementation = options.fetchImplementation ?? fetch;
  }

  public async request<T>(path: string, init: RequestInit = {}): Promise<TestHttpResponse<T>> {
    const headers = new Headers(init.headers);

    const response = await this.fetchImplementation(new URL(path, this.baseUrl), {
      ...init,
      credentials: 'omit',
      headers,
    });

    const body = await this.parseBody<T>(response);
    return {
      status: response.status,
      requestId: response.headers.get('x-request-id'),
      body,
    };
  }

  private async parseBody<T>(response: Response): Promise<T | null> {
    const contentType = response.headers.get('content-type') ?? '';
    if (!contentType.includes('application/json')) {
      return null;
    }
    return (await response.json()) as T;
  }
}
