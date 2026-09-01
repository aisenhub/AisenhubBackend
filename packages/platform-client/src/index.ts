import {
  AccessResponseSchema,
  AccountDeletionRequestSchema,
  ApiSuccessEnvelopeSchema,
  EntitlementsResponseSchema,
  FeedbackRequestSchema,
  FeedbackResponseSchema,
  PublicProductsResponseSchema,
  RedemptionRequestSchema,
  RedemptionResponseSchema,
  type AccountDeletionRequest,
  SessionDeleteResponseSchema,
  SessionExchangeResponseSchema,
  SessionResponseSchema,
  parseApiError,
  type SessionDeleteResponse,
  type SessionExchangeResponse,
  type SessionResponse,
  type ApiErrorEnvelope,
  type ContractSchema,
  type EntitlementsResponse,
  type FeedbackRequest,
  type FeedbackResponse,
  type PublicProductsResponse,
  type RedemptionResponse,
  type AccessResponse,
  type RequestId,
} from '@aisenhub/contracts';

export interface PlatformClientOptions {
  baseUrl: string;
  publicBaseUrl?: string;
  fetch?: typeof globalThis.fetch;
  csrfToken?: () => string | undefined;
  appSlug?: string;
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
  exchangeSession(accessToken: string): Promise<PlatformResponse<SessionExchangeResponse>>;
  getSession(): Promise<PlatformResponse<SessionResponse>>;
  logout(): Promise<PlatformResponse<SessionDeleteResponse>>;
  getPublicProducts(): Promise<PlatformResponse<PublicProductsResponse>>;
  getEntitlements(): Promise<PlatformResponse<EntitlementsResponse>>;
  checkAccess(featureCode: string): Promise<PlatformResponse<AccessResponse>>;
  redeem(code: string, idempotencyKey: string): Promise<PlatformResponse<RedemptionResponse>>;
  submitFeedback(input: FeedbackRequest): Promise<PlatformResponse<FeedbackResponse>>;
  requestAccountDeletion(
    accessToken: string,
    idempotencyKey: string,
  ): Promise<PlatformResponse<AccountDeletionRequest>>;
  cancelAccountDeletion(accessToken: string): Promise<PlatformResponse<AccountDeletionRequest>>;
}

export function createPlatformClient(options: PlatformClientOptions): PlatformClient {
  const requestFetch = options.fetch ?? globalThis.fetch;
  const baseUrl = options.baseUrl.replace(/\/$/, '');
  const publicBaseUrl = (options.publicBaseUrl ?? options.baseUrl).replace(/\/$/, '');

  return {
    async request<T>(
      path: string,
      responseSchema: ContractSchema<T>,
      init: RequestInit = {},
    ): Promise<PlatformResponse<T>> {
      return requestAtBase(baseUrl, path, responseSchema, init);
    },
    async getPublicProducts() {
      return requestAtBase(publicBaseUrl, '/v1/products/public', PublicProductsResponseSchema);
    },
    exchangeSession(accessToken: string) {
      if (accessToken.trim() === '') throw new Error('An access token is required.');
      return this.request('/v1/session/exchange', SessionExchangeResponseSchema, {
        method: 'POST',
        headers: { authorization: `Bearer ${accessToken}` },
      });
    },
    getSession() {
      return this.request('/v1/session', SessionResponseSchema);
    },
    logout() {
      return this.request('/v1/session', SessionDeleteResponseSchema, { method: 'DELETE' });
    },
    getEntitlements() {
      return this.request('/v1/me/entitlements', EntitlementsResponseSchema);
    },
    checkAccess(featureCode: string) {
      if (!/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/.test(featureCode)) {
        throw new Error('A valid feature code is required.');
      }
      return this.request(`/v1/access/${encodeURIComponent(featureCode)}`, AccessResponseSchema);
    },
    redeem(code: string, idempotencyKey: string) {
      const normalizedCode = code.trim();
      const normalizedIdempotencyKey = idempotencyKey.trim();
      if (normalizedIdempotencyKey === '' || normalizedIdempotencyKey.length > 255) {
        throw new Error('A valid Idempotency-Key is required.');
      }
      const request = RedemptionRequestSchema.parse({ code: normalizedCode });
      return this.request('/v1/redemptions', RedemptionResponseSchema, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'idempotency-key': normalizedIdempotencyKey,
        },
        body: JSON.stringify(request),
      });
    },
    submitFeedback(input: FeedbackRequest) {
      const request = FeedbackRequestSchema.parse(input);
      return this.request('/v1/feedback', FeedbackResponseSchema, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(request),
      });
    },
    requestAccountDeletion(accessToken: string, idempotencyKey: string) {
      const normalizedToken = accessToken.trim();
      const normalizedIdempotencyKey = idempotencyKey.trim();
      if (normalizedToken === '') throw new Error('A reauthentication access token is required.');
      if (normalizedIdempotencyKey === '' || normalizedIdempotencyKey.length > 255) {
        throw new Error('A valid Idempotency-Key is required.');
      }
      return this.request('/v1/me/deletion-requests', AccountDeletionRequestSchema, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${normalizedToken}`,
          'idempotency-key': normalizedIdempotencyKey,
          'content-type': 'application/json',
        },
        body: '{}',
      });
    },
    cancelAccountDeletion(accessToken: string) {
      const normalizedToken = accessToken.trim();
      if (normalizedToken === '') throw new Error('A reauthentication access token is required.');
      return this.request('/v1/me/deletion-requests', AccountDeletionRequestSchema, {
        method: 'DELETE',
        headers: { authorization: `Bearer ${normalizedToken}` },
      });
    },
  };

  async function requestAtBase<T>(
    requestBaseUrl: string,
    path: string,
    responseSchema: ContractSchema<T>,
    init: RequestInit = {},
  ): Promise<PlatformResponse<T>> {
    const headers = new Headers(init.headers);
    headers.set('accept', 'application/json');
    if (options.appSlug) headers.set('x-aisenhub-app', options.appSlug);
    const csrfToken = options.csrfToken?.();
    if (csrfToken) headers.set('x-csrf-token', csrfToken);

    const response = await requestFetch(`${requestBaseUrl}${path}`, {
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
  }
}
