import type { ApiErrorEnvelope, RequestId } from '@aisenhub/contracts';

export interface AdminClientOptions {
  baseUrl: string;
  fetch?: typeof globalThis.fetch;
}

export interface AdminResponse<T> {
  data: T;
  requestId: RequestId;
}

export type AdminApiError = ApiErrorEnvelope;

export type AdminClient = Readonly<AdminClientOptions>;

export function createAdminClient(options: AdminClientOptions): AdminClient {
  return Object.freeze({ ...options });
}
