import {
  AccessResponseSchema,
  AccountDeletionRequestSchema,
  ApiSuccessEnvelopeSchema,
  ApplicationContextResponseSchema,
  ApplicationMembershipCommandResponseSchema,
  EntitlementsResponseSchema,
  FeedbackRequestSchema,
  FeedbackResponseSchema,
  MeResponseSchema,
  MyApplicationsResponseSchema,
  PublicProductsResponseSchema,
  RedemptionRequestSchema,
  RedemptionResponseSchema,
  parseApiError,
  type AccountDeletionRequest,
  type AccessResponse,
  type ApiErrorEnvelope,
  type ApplicationContextResponse,
  type ApplicationMembershipCommandResponse,
  type ContractSchema,
  type EntitlementsResponse,
  type FeedbackRequest,
  type FeedbackResponse,
  type MeResponse,
  type MyApplicationsResponse,
  type PublicProductsResponse,
  type RedemptionResponse,
  type RequestId,
} from '@aisenhub/contracts';

export interface PlatformClientOptions {
  baseUrl: string;
  publicBaseUrl?: string;
  fetch?: typeof globalThis.fetch;
  accessToken?: () => string | null | undefined;
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
  getProfile(): Promise<PlatformResponse<MeResponse>>;
  getApplicationContext(): Promise<PlatformResponse<ApplicationContextResponse>>;
  getApplications(): Promise<PlatformResponse<MyApplicationsResponse>>;
  leaveApplication(
    membershipId: string,
    reason: string,
    idempotencyKey: string,
  ): Promise<PlatformResponse<ApplicationMembershipCommandResponse>>;
  getPublicProducts(): Promise<PlatformResponse<PublicProductsResponse>>;
  getEntitlements(): Promise<PlatformResponse<EntitlementsResponse>>;
  checkAccess(featureCode: string): Promise<PlatformResponse<AccessResponse>>;
  redeem(code: string, idempotencyKey: string): Promise<PlatformResponse<RedemptionResponse>>;
  submitFeedback(input: FeedbackRequest): Promise<PlatformResponse<FeedbackResponse>>;
  requestAccountDeletion(idempotencyKey: string): Promise<PlatformResponse<AccountDeletionRequest>>;
  cancelAccountDeletion(): Promise<PlatformResponse<AccountDeletionRequest>>;
}

export function createPlatformClient(options: PlatformClientOptions): PlatformClient {
  const requestFetch = options.fetch ?? globalThis.fetch.bind(globalThis);
  const baseUrl = options.baseUrl.replace(/\/$/, '');
  const publicBaseUrl = (options.publicBaseUrl ?? options.baseUrl).replace(/\/$/, '');

  return {
    request<T>(path: string, responseSchema: ContractSchema<T>, init: RequestInit = {}) {
      return requestAtBase(baseUrl, path, responseSchema, init, true);
    },
    getProfile() {
      return requestAtBase(baseUrl, '/v1/account/me', MeResponseSchema, {}, true);
    },
    getApplicationContext() {
      return requestAtBase(baseUrl, '/v1/app/context', ApplicationContextResponseSchema, {}, true);
    },
    getApplications() {
      return requestAtBase(
        baseUrl,
        '/v1/account/applications',
        MyApplicationsResponseSchema,
        {},
        true,
      );
    },
    leaveApplication(membershipId, reason, idempotencyKey) {
      const normalizedIdempotencyKey = idempotencyKey.trim();
      if (!normalizedIdempotencyKey || normalizedIdempotencyKey.length > 255) {
        throw new Error('A valid Idempotency-Key is required.');
      }
      if (
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
          membershipId,
        )
      ) {
        throw new Error('A valid membership ID is required.');
      }
      return requestAtBase(
        baseUrl,
        `/v1/account/applications/${encodeURIComponent(membershipId)}/leave`,
        ApplicationMembershipCommandResponseSchema,
        {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'idempotency-key': normalizedIdempotencyKey,
          },
          body: JSON.stringify({ reason: reason.trim() }),
        },
        true,
      );
    },
    getPublicProducts() {
      return requestAtBase(
        publicBaseUrl,
        '/v1/products/public',
        PublicProductsResponseSchema,
        {},
        false,
      );
    },
    getEntitlements() {
      return requestAtBase(baseUrl, '/v1/app/entitlements', EntitlementsResponseSchema, {}, true);
    },
    checkAccess(featureCode) {
      if (!/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/.test(featureCode)) {
        throw new Error('A valid feature code is required.');
      }
      return requestAtBase(
        baseUrl,
        `/v1/app/access/${encodeURIComponent(featureCode)}`,
        AccessResponseSchema,
        {},
        true,
      );
    },
    redeem(code, idempotencyKey) {
      const normalizedIdempotencyKey = idempotencyKey.trim();
      if (normalizedIdempotencyKey === '' || normalizedIdempotencyKey.length > 255) {
        throw new Error('A valid Idempotency-Key is required.');
      }
      const request = RedemptionRequestSchema.parse({ code: code.trim() });
      return requestAtBase(
        baseUrl,
        '/v1/app/redemptions',
        RedemptionResponseSchema,
        {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'idempotency-key': normalizedIdempotencyKey,
          },
          body: JSON.stringify(request),
        },
        true,
      );
    },
    submitFeedback(input) {
      const request = FeedbackRequestSchema.parse(input);
      return requestAtBase(
        baseUrl,
        '/v1/app/feedback',
        FeedbackResponseSchema,
        {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(request),
        },
        true,
      );
    },
    requestAccountDeletion(idempotencyKey) {
      const normalizedIdempotencyKey = idempotencyKey.trim();
      if (normalizedIdempotencyKey === '' || normalizedIdempotencyKey.length > 255) {
        throw new Error('A valid Idempotency-Key is required.');
      }
      return requestAtBase(
        baseUrl,
        '/v1/account/deletion-requests',
        AccountDeletionRequestSchema,
        {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'idempotency-key': normalizedIdempotencyKey,
          },
          body: '{}',
        },
        true,
      );
    },
    cancelAccountDeletion() {
      return requestAtBase(
        baseUrl,
        '/v1/account/deletion-requests',
        AccountDeletionRequestSchema,
        { method: 'DELETE' },
        true,
      );
    },
  };

  async function requestAtBase<T>(
    requestBaseUrl: string,
    path: string,
    responseSchema: ContractSchema<T>,
    init: RequestInit,
    authenticated: boolean,
  ): Promise<PlatformResponse<T>> {
    const headers = new Headers(init.headers);
    headers.set('accept', 'application/json');
    if (authenticated) {
      const token = options.accessToken?.()?.trim();
      if (!token) throw new Error('An access token is required.');
      headers.set('authorization', `Bearer ${token}`);
    }

    const response = await requestFetch(`${requestBaseUrl}${path}`, {
      ...init,
      credentials: 'omit',
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
      return { data: envelope.data, requestId: envelope.requestId };
    } catch {
      throw new PlatformClientError('The API returned an invalid success response.', {
        code: 'MALFORMED_API_RESPONSE',
        requestId: responseRequestId,
        status: response.status,
      });
    }
  }
}
