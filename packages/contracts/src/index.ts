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
  ADMIN_RESOURCE_NOT_FOUND: 'ADMIN_RESOURCE_NOT_FOUND',
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

export {
  AdminRoles,
  AdminRoleSchema,
  PermissionActions,
  PermissionActionSchema,
} from './admin-registry';
export type { AdminRole, PermissionAction } from './admin-registry';
export { AdminActionMatrix, evaluateAdminAction, getAdminActionPolicy } from './admin-permissions';
export type {
  AdminActionPolicy,
  AdminAuthorizationContext,
  AdminAuthorizationDecision,
} from './admin-permissions';

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
  AdminCatalogResourceQuerySchema,
  AdminChangeProductionOriginRequestSchema,
  AdminCreateApplicationRequestSchema,
  AdminCreateFeatureRequestSchema,
  AdminCreateOriginRequestSchema,
  AdminCreatePriceRequestSchema,
  AdminCreateProductRequestSchema,
  AdminCreateProductVersionRequestSchema,
  AdminCloseRedemptionBatchRequestSchema,
  AdminCommandMetadataSchema,
  AdminGenerateRedemptionCodesRequestSchema,
  AdminGenerateRedemptionCodesResponseSchema,
  AdminGeneratedRedemptionCodeSchema,
  AdminPauseRedemptionBatchRequestSchema,
  AdminProductListResponseSchema,
  AdminCurrentProductVersionCommandResponseSchema,
  AdminProductSummarySchema,
  AdminProductVersionCommandResponseSchema,
  AdminProductVersionListResponseSchema,
  AdminProductVersionSummarySchema,
  AdminProductionOriginCommandResponseSchema,
  AdminPublishProductVersionRequestSchema,
  AdminRedemptionBatchCommandResponseSchema,
  AdminRedemptionBatchListResponseSchema,
  AdminRedemptionBatchSummarySchema,
  AdminRedemptionCodeListResponseSchema,
  AdminRedemptionCodeSummarySchema,
  AdminRedemptionListResponseSchema,
  AdminRedemptionSummarySchema,
  AdminFeatureListResponseSchema,
  AdminFeatureSnapshotSchema,
  AdminFeatureSummarySchema,
  AdminOriginListResponseSchema,
  AdminOriginSummarySchema,
  AdminPriceListResponseSchema,
  AdminPriceSummarySchema,
  AdminProductOverviewSchema,
  AdminRetireProductVersionRequestSchema,
  AdminSetCurrentProductVersionRequestSchema,
  AdminUpdateApplicationRequestSchema,
  AdminUpdateFeatureRequestSchema,
  AdminUpdateOriginRequestSchema,
  AdminUpdatePriceRequestSchema,
  AdminUpdateProductRequestSchema,
  AdminUpdateProductVersionRequestSchema,
} from './admin-catalog';

export {
  AdminApplicationListResponseSchema,
  AdminApplicationSummarySchema,
  AdminAuditLogListResponseSchema,
  AdminAuditLogSummarySchema,
  AdminEntitlementListResponseSchema,
  AdminEntitlementSummarySchema,
  AdminFeedbackListResponseSchema,
  AdminFeedbackSummarySchema,
  AdminQueryListQuerySchema,
  AdminSystemHealthCheckSchema,
  AdminSystemHealthResponseSchema,
  AdminUserListResponseSchema,
  AdminUserSummarySchema,
} from './admin-operations';

export type {
  AdminApplicationListResponse,
  AdminApplicationSummary,
  AdminAuditLogListResponse,
  AdminAuditLogSummary,
  AdminEntitlementListResponse,
  AdminEntitlementSummary,
  AdminFeedbackListResponse,
  AdminFeedbackSummary,
  AdminQueryListQuery,
  AdminSystemHealthCheck,
  AdminSystemHealthResponse,
  AdminUserListResponse,
  AdminUserSummary,
} from './admin-operations';

export type {
  AdminCatalogListQuery,
  AdminCatalogResourceQuery,
  AdminChangeProductionOriginRequest,
  AdminCreateApplicationRequest,
  AdminCreateFeatureRequest,
  AdminCreateOriginRequest,
  AdminCreatePriceRequest,
  AdminCreateProductRequest,
  AdminCreateProductVersionRequest,
  AdminCloseRedemptionBatchRequest,
  AdminCommandMetadata,
  AdminGenerateRedemptionCodesRequest,
  AdminGenerateRedemptionCodesResponse,
  AdminGeneratedRedemptionCode,
  AdminPauseRedemptionBatchRequest,
  AdminProductListResponse,
  AdminCurrentProductVersionCommandResponse,
  AdminProductSummary,
  AdminProductVersionCommandResponse,
  AdminProductVersionListResponse,
  AdminProductVersionSummary,
  AdminProductionOriginCommandResponse,
  AdminPublishProductVersionRequest,
  AdminRedemptionBatchCommandResponse,
  AdminRedemptionBatchListResponse,
  AdminRedemptionBatchSummary,
  AdminRedemptionCodeListResponse,
  AdminRedemptionCodeSummary,
  AdminRedemptionListResponse,
  AdminRedemptionSummary,
  AdminFeatureListResponse,
  AdminFeatureSnapshot,
  AdminFeatureSummary,
  AdminOriginListResponse,
  AdminOriginSummary,
  AdminPriceListResponse,
  AdminPriceSummary,
  AdminProductOverview,
  AdminRetireProductVersionRequest,
  AdminSetCurrentProductVersionRequest,
  AdminUpdateApplicationRequest,
  AdminUpdateFeatureRequest,
  AdminUpdateOriginRequest,
  AdminUpdatePriceRequest,
  AdminUpdateProductRequest,
  AdminUpdateProductVersionRequest,
} from './admin-catalog';
