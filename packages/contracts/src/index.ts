export const API_VERSION = 'v1' as const;

export type RequestId = string;

export interface ApiErrorEnvelope {
  error: {
    code: string;
    message: string;
    details?: Readonly<Record<string, unknown>>;
  };
  requestId: RequestId;
}
