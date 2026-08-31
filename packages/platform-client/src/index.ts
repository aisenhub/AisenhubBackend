import {
  ApiSuccessEnvelopeSchema,
  parseApiError,
  type ApiErrorEnvelope,
  type ContractSchema,
  type RequestId,
} from '@aisenhub/contracts';

export interface PlatformClientOptions {
  baseUrl: string;
  fetch?: typeof globalThis.fetch;
  csrfToken?: () => string | undefined;
}

export interface PlatformResponse<T> {
  data: T;
  requestId: RequestId;
}

export type PlatformApiError = ApiErrorEnvelope;

export class PlatformClientError extends Error {
  readonly code: string;
  readonly requestId?: string;
  readonly status: number;
  readonly details?: Readonly<Record<string, unknown>>;

  constructor(
    message: string,
    options: {
      code: string;
      requestId?: string;
      status: number;
      details?: Readonly<Record<string, unknown>>;
    },
  ) {
    super(message);
    this.name = 'PlatformClientError';
    this.code = options.code;
    this.requestId = options.requestId;
    this.status = options.status;
    this.details = options.details;
  }
}

export interface PlatformClient {
  request<T>(
    path: string,
    responseSchema: ContractSchema<T>,
    init?: RequestInit,
  ): Promise<PlatformResponse<T>>;
}

export function createPlatformClient(options: PlatformClientOptions): PlatformClient {
  const requestFetch = options.fetch ?? globalThis.fetch;
  const baseUrl = options.baseUrl.replace(/\/$/, '');

  return {
    async request<T>(
      path: string,
      responseSchema: ContractSchema<T>,
      init: RequestInit = {},
    ): Promise<PlatformResponse<T>> {
      const headers = new Headers(init.headers);
      headers.set('accept', 'application/json');
      const csrfToken = options.csrfToken?.();
      if (csrfToken) headers.set('x-csrf-token', csrfToken);

      const response = await requestFetch(`${baseUrl}${path}`, {
        ...init,
        credentials: 'include',
        headers,
      });
      const responseRequestId = response.headers.get('x-request-id') ?? undefined;
      let payload: unknown;
      try {
        payload = await response.json();
      } catch {
        throw new PlatformClientError('The API returned an invalid JSON response.', {
          code: 'MALFORMED_API_RESPONSE',
          requestId: responseRequestId,
          status: response.status,
        });
      }

      if (!response.ok) {
        try {
          const error = parseApiError(payload);
          throw new PlatformClientError(error.error.message, {
            code: error.error.code,
            details: error.error.details,
            requestId: error.error.requestId,
            status: response.status,
          });
        } catch (error) {
          if (error instanceof PlatformClientError) throw error;
          throw new PlatformClientError('The API returned an invalid error response.', {
            code: 'MALFORMED_API_RESPONSE',
            requestId: responseRequestId,
            status: response.status,
          });
        }
      }

      try {
        const envelope = ApiSuccessEnvelopeSchema(responseSchema).parse(payload);
        return {
          data: envelope.data,
          requestId: envelope.requestId,
        };
      } catch {
        throw new PlatformClientError('The API returned an invalid success response.', {
          code: 'MALFORMED_API_RESPONSE',
          requestId: responseRequestId,
          status: response.status,
        });
      }
    },
  };
}
