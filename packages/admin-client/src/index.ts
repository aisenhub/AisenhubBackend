import {
  ApiSuccessEnvelopeSchema,
  parseApiError,
  type ApiErrorEnvelope,
  type ContractSchema,
  type ErrorCode,
  type RequestId,
} from '@aisenhub/contracts';

export interface AdminClientOptions {
  baseUrl: string;
  accessToken?: () => string | null | undefined;
  fetch?: typeof globalThis.fetch;
}

export interface AdminResponse<T> {
  data: T;
  requestId: RequestId;
}

export type AdminApiError = ApiErrorEnvelope;

export class AdminClientError extends Error {
  readonly code: ErrorCode | 'MALFORMED_API_RESPONSE';
  readonly requestId?: string;
  readonly status: number;
  readonly details?: Readonly<Record<string, unknown>>;

  constructor(
    message: string,
    options: {
      code: ErrorCode | 'MALFORMED_API_RESPONSE';
      requestId?: string;
      status: number;
      details?: Readonly<Record<string, unknown>>;
    },
  ) {
    super(message);
    this.name = 'AdminClientError';
    this.code = options.code;
    this.requestId = options.requestId;
    this.status = options.status;
    this.details = options.details;
  }
}

export interface AdminRequestInit extends RequestInit {
  idempotencyKey?: string;
}

export interface AdminClient {
  request<T>(
    path: string,
    responseSchema: ContractSchema<T>,
    init?: AdminRequestInit,
  ): Promise<AdminResponse<T>>;
}

export function withIdempotencyKey(init: RequestInit = {}, key?: string): AdminRequestInit {
  const idempotencyKey = key ?? globalThis.crypto?.randomUUID();
  if (!idempotencyKey) throw new Error('An Idempotency-Key is required.');
  const headers = new Headers(init.headers);
  headers.set('Idempotency-Key', idempotencyKey);
  return { ...init, headers, idempotencyKey };
}

export function createAdminClient(options: AdminClientOptions): AdminClient {
  const requestFetch = options.fetch ?? globalThis.fetch;
  const baseUrl = options.baseUrl.replace(/\/$/, '');

  return {
    async request<T>(
      path: string,
      responseSchema: ContractSchema<T>,
      init: AdminRequestInit = {},
    ): Promise<AdminResponse<T>> {
      const headers = new Headers(init.headers);
      headers.set('accept', 'application/json');
      const accessToken = options.accessToken?.();
      if (accessToken) headers.set('authorization', `Bearer ${accessToken}`);
      if (init.idempotencyKey) headers.set('Idempotency-Key', init.idempotencyKey);

      const response = await requestFetch(`${baseUrl}${path}`, {
        ...init,
        credentials: 'omit',
        headers,
      });
      const responseRequestId = response.headers.get('x-request-id') ?? undefined;
      let payload: unknown;
      try {
        payload = await response.json();
      } catch {
        throw new AdminClientError('The API returned an invalid JSON response.', {
          code: 'MALFORMED_API_RESPONSE',
          requestId: responseRequestId,
          status: response.status,
        });
      }

      if (!response.ok) {
        try {
          const error = parseApiError(payload);
          throw new AdminClientError(error.error.message, {
            code: error.error.code,
            details: error.error.details,
            requestId: error.error.requestId,
            status: response.status,
          });
        } catch (error) {
          if (error instanceof AdminClientError) throw error;
          throw new AdminClientError('The API returned an invalid error response.', {
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
        throw new AdminClientError('The API returned an invalid success response.', {
          code: 'MALFORMED_API_RESPONSE',
          requestId: responseRequestId,
          status: response.status,
        });
      }
    },
  };
}

export { AdminResourceNames, createAdminDataProvider } from './data-provider';
export type {
  AdminListResult,
  AdminResourceItem,
  AdminResourceName,
  AdminResourceQuery,
  AdminDraftMutationOptions,
  AisenHubAdminDataProvider,
} from './data-provider';

export { createBusinessCommandClient } from './command-client';
export type {
  AdminCommandOptions,
  AdminCommandResult,
  AisenHubBusinessCommandClient,
} from './command-client';
