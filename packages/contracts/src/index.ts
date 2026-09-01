import { z } from 'zod';

export const API_VERSION = 'v1' as const;

export const RequestIdSchema = z.string().uuid();
export type RequestId = z.infer<typeof RequestIdSchema>;
export interface ContractSchema<T> {
  parse(input: unknown): T;
}

export const ErrorCodes = {
  APP_ORIGIN_MISMATCH: 'APP_ORIGIN_MISMATCH',
  APP_NOT_FOUND: 'APP_NOT_FOUND',
  ADMIN_ACCESS_DENIED: 'ADMIN_ACCESS_DENIED',
  ACCOUNT_DISABLED: 'ACCOUNT_DISABLED',
  AUTHENTICATION_REQUIRED: 'AUTHENTICATION_REQUIRED',
  CSRF_INVALID: 'CSRF_INVALID',
  INTERNAL_ERROR: 'INTERNAL_ERROR',
  INVALID_STATE_TRANSITION: 'INVALID_STATE_TRANSITION',
  IDEMPOTENCY_KEY_REUSED: 'IDEMPOTENCY_KEY_REUSED',
  MFA_REQUIRED: 'MFA_REQUIRED',
  ORIGIN_NOT_ALLOWED: 'ORIGIN_NOT_ALLOWED',
  PROFILE_NOT_FOUND: 'PROFILE_NOT_FOUND',
  REASON_REQUIRED: 'REASON_REQUIRED',
  REDEMPTION_UNAVAILABLE: 'REDEMPTION_UNAVAILABLE',
  RESOURCE_VERSION_CONFLICT: 'RESOURCE_VERSION_CONFLICT',
  SESSION_EXPIRED: 'SESSION_EXPIRED',
  SESSION_REVOKED: 'SESSION_REVOKED',
  VALIDATION_ERROR: 'VALIDATION_ERROR',
} as const;

export const ErrorCodeSchema = z.enum(Object.values(ErrorCodes) as [string, ...string[]]);
export type ErrorCode = z.infer<typeof ErrorCodeSchema>;

const ErrorDetailsSchema = z.record(z.string(), z.unknown());

export const ApiErrorSchema = z.object({
  code: ErrorCodeSchema,
  message: z.string().min(1),
  requestId: RequestIdSchema,
  details: ErrorDetailsSchema.optional(),
});

export const ApiErrorEnvelopeSchema = z.object({
  error: ApiErrorSchema,
});

export interface ApiErrorEnvelope {
  error: z.infer<typeof ApiErrorSchema>;
}

export function parseApiError(input: unknown): ApiErrorEnvelope {
  return ApiErrorEnvelopeSchema.parse(input);
}

export type ApiSuccessEnvelope<T> = {
  data: T;
  requestId: RequestId;
};

export const ApiSuccessEnvelopeSchema = <T>(
  dataSchema: ContractSchema<T>,
): z.ZodType<ApiSuccessEnvelope<T>> =>
  z
    .object({
      data: z.unknown(),
      requestId: RequestIdSchema,
    })
    .transform(({ data, requestId }) => ({
      data: dataSchema.parse(data),
      requestId,
    }));

export { PageMetaSchema, PaginationQuerySchema } from './pagination';
export type { PageMeta, PaginationQuery } from './pagination';

export const PermissionActions = [
  'applications.read',
  'applications.change_production_origin',
  'products.read',
  'products.create',
  'product_versions.publish',
  'product_versions.retire',
  'product_versions.set_current',
  'redemption_batches.generate_codes',
  'redemption_batches.pause',
  'redemption_batches.close',
  'entitlements.grant',
  'entitlements.revoke',
  'entitlements.restore',
  'orders.read',
  'order_items.refund',
  'admin_members.manage',
  'audit_logs.read',
] as const;

export const PermissionActionSchema = z.enum(PermissionActions);
export type PermissionAction = (typeof PermissionActions)[number];

export const AdminRoles = ['owner', 'admin', 'support', 'finance'] as const;
export const AdminRoleSchema = z.enum(AdminRoles);
export type AdminRole = (typeof AdminRoles)[number];

export {
  AdminAalSchema,
  AdminMfaStateSchema,
  AdminSessionResponseSchema,
  AnonymousSessionSchema,
  ApplicationIdentitySchema,
  AuthenticatedSessionSchema,
  IsoDateTimeSchema,
  MeResponseSchema,
  ProfileIdentitySchema,
  ProfileStatusSchema,
  SessionDeleteResponseSchema,
  SessionExchangeRequestSchema,
  SessionExchangeResponseSchema,
  SessionResponseSchema,
  UserIdSchema,
} from './identity';

export type {
  AdminAal,
  AdminMfaState,
  AdminSessionResponse,
  ApplicationIdentity,
  MeResponse,
  ProfileIdentity,
  ProfileStatus,
  SessionDeleteResponse,
  SessionExchangeRequest,
  SessionExchangeResponse,
  SessionResponse,
  UserId,
} from './identity';

export {
  AccessResponseSchema,
  EntitlementSummarySchema,
  EntitlementsResponseSchema,
  FeedbackRequestSchema,
  FeedbackResponseSchema,
  PublicProductSchema,
  PublicProductsResponseSchema,
  RedemptionRequestSchema,
  RedemptionResponseSchema,
} from './catalog';

export type {
  AccessResponse,
  EntitlementSummary,
  EntitlementsResponse,
  FeedbackRequest,
  FeedbackResponse,
  PublicProduct,
  PublicProductsResponse,
  RedemptionRequest,
  RedemptionResponse,
} from './catalog';

export {
  AdminCatalogListQuerySchema,
  AdminCloseRedemptionBatchRequestSchema,
  AdminCommandMetadataSchema,
  AdminGenerateRedemptionCodesRequestSchema,
  AdminGenerateRedemptionCodesResponseSchema,
  AdminGeneratedRedemptionCodeSchema,
  AdminPauseRedemptionBatchRequestSchema,
  AdminProductListResponseSchema,
  AdminProductSummarySchema,
  AdminProductVersionCommandResponseSchema,
  AdminProductVersionListResponseSchema,
  AdminProductVersionSummarySchema,
  AdminPublishProductVersionRequestSchema,
  AdminRedemptionBatchCommandResponseSchema,
  AdminRedemptionBatchListResponseSchema,
  AdminRedemptionBatchSummarySchema,
  AdminRedemptionCodeSummarySchema,
  AdminRedemptionSummarySchema,
  AdminRetireProductVersionRequestSchema,
  AdminSetCurrentProductVersionRequestSchema,
} from './admin-catalog';

export type {
  AdminCatalogListQuery,
  AdminCloseRedemptionBatchRequest,
  AdminCommandMetadata,
  AdminGenerateRedemptionCodesRequest,
  AdminGenerateRedemptionCodesResponse,
  AdminGeneratedRedemptionCode,
  AdminPauseRedemptionBatchRequest,
  AdminProductListResponse,
  AdminProductSummary,
  AdminProductVersionCommandResponse,
  AdminProductVersionListResponse,
  AdminProductVersionSummary,
  AdminPublishProductVersionRequest,
  AdminRedemptionBatchCommandResponse,
  AdminRedemptionBatchListResponse,
  AdminRedemptionBatchSummary,
  AdminRedemptionCodeSummary,
  AdminRedemptionSummary,
  AdminRetireProductVersionRequest,
  AdminSetCurrentProductVersionRequest,
} from './admin-catalog';
