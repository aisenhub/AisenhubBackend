import type { ApiErrorEnvelope, RequestId } from '@aisenhub/contracts';

export interface PlatformClientOptions {
  baseUrl: string;
  fetch?: typeof globalThis.fetch;
}

export interface PlatformResponse<T> {
  data: T;
  requestId: RequestId;
}

export type PlatformApiError = ApiErrorEnvelope;

export type PlatformClient = Readonly<PlatformClientOptions>;

export function createPlatformClient(options: PlatformClientOptions): PlatformClient {
  return Object.freeze({ ...options });
}
