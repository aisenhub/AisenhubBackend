import { z } from 'zod';

import { IsoDateTimeSchema, UserIdSchema } from './identity';
import { PageMetaSchema } from './pagination';
import { AdminAuditLogSummarySchema } from './admin-operations';

const UuidSchema = z.string().uuid();

export const AdminCatalogListQuerySchema = z
  .object({
    cursor: z.string().min(1).max(512).optional(),
    limit: z.coerce.number().int().min(1).max(100).default(25),
    search: z.string().min(1).max(200).optional(),
    status: z
      .enum(['draft', 'active', 'archived', 'published', 'retired', 'paused', 'closed'])
      .optional(),
    sort: z.enum(['createdAt', 'updatedAt', 'name', 'sku', 'status']).default('createdAt'),
    direction: z.enum(['asc', 'desc']).default('desc'),
  })
  .strict();
export type AdminCatalogListQuery = z.infer<typeof AdminCatalogListQuerySchema>;

export const AdminCatalogResourceQuerySchema = z
  .object({
    cursor: z.string().min(1).max(512).optional(),
    limit: z.coerce.number().int().min(1).max(100).default(25),
    search: z.string().min(1).max(200).optional(),
    status: z.string().min(1).max(50).optional(),
    sort: z
      .enum([
        'createdAt',
        'updatedAt',
        'name',
        'sku',
        'status',
        'origin',
        'environment',
        'code',
        'version',
        'channel',
        'validFrom',
        'redeemedAt',
      ])
      .default('createdAt'),
    direction: z.enum(['asc', 'desc']).default('desc'),
  })
  .strict();
export type AdminCatalogResourceQuery = z.infer<typeof AdminCatalogResourceQuerySchema>;

const AdminDraftReasonSchema = z.string().trim().min(1).max(1000);
const AdminExactOriginSchema = z
  .string()
  .regex(/^https?:\/\/[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?$/);
const AdminMetadataSchema = z.record(z.string(), z.unknown());

export const AdminCreateApplicationRequestSchema = z
  .object({
    slug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
    name: z.string().trim().min(1).max(200),
    category: z.string().trim().min(1).max(100),
    metadata: AdminMetadataSchema.optional(),
    reason: AdminDraftReasonSchema,
  })
  .strict();
export type AdminCreateApplicationRequest = z.infer<typeof AdminCreateApplicationRequestSchema>;

export const AdminUpdateApplicationRequestSchema = z
  .object({
    name: z.string().trim().min(1).max(200).optional(),
    category: z.string().trim().min(1).max(100).optional(),
    metadata: AdminMetadataSchema.optional(),
    expectedUpdatedAt: IsoDateTimeSchema,
    reason: AdminDraftReasonSchema,
  })
  .strict()
  .refine(
    (value) =>
      value.name !== undefined || value.category !== undefined || value.metadata !== undefined,
    {
      message: 'At least one application draft field is required',
    },
  );
export type AdminUpdateApplicationRequest = z.infer<typeof AdminUpdateApplicationRequestSchema>;

export const AdminCreateOriginRequestSchema = z
  .object({
    environment: z.enum(['development', 'staging']),
    origin: AdminExactOriginSchema,
    reason: AdminDraftReasonSchema,
  })
  .strict();
export type AdminCreateOriginRequest = z.infer<typeof AdminCreateOriginRequestSchema>;

export const AdminUpdateOriginRequestSchema = z
  .object({
    isActive: z.boolean(),
    expectedUpdatedAt: IsoDateTimeSchema,
    reason: AdminDraftReasonSchema,
  })
  .strict();
export type AdminUpdateOriginRequest = z.infer<typeof AdminUpdateOriginRequestSchema>;

const AdminFeatureMergeStrategySchema = z.enum(['any_true', 'sum', 'max', 'min', 'latest']);
export const AdminCreateFeatureRequestSchema = z
  .object({
    appId: UuidSchema.optional().nullable(),
    code: z.string().regex(/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/),
    name: z.string().trim().min(1).max(200),
    valueType: z.enum(['boolean', 'integer', 'string', 'json']),
    mergeStrategy: AdminFeatureMergeStrategySchema,
    reason: AdminDraftReasonSchema,
  })
  .strict();
export type AdminCreateFeatureRequest = z.infer<typeof AdminCreateFeatureRequestSchema>;

export const AdminUpdateFeatureRequestSchema = z
  .object({
    name: z.string().trim().min(1).max(200).optional(),
    mergeStrategy: AdminFeatureMergeStrategySchema.optional(),
    reason: AdminDraftReasonSchema,
  })
  .strict()
  .refine((value) => value.name !== undefined || value.mergeStrategy !== undefined, {
    message: 'At least one feature draft field is required',
  });
export type AdminUpdateFeatureRequest = z.infer<typeof AdminUpdateFeatureRequestSchema>;

export const AdminCreateProductRequestSchema = z
  .object({
    sku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    name: z.string().trim().min(1).max(200),
    billingType: z.enum(['one_time', 'subscription', 'credits']),
    entitlementPolicy: z.enum(['snapshot', 'all_apps_access']).optional(),
    reason: AdminDraftReasonSchema,
  })
  .strict();
export type AdminCreateProductRequest = z.infer<typeof AdminCreateProductRequestSchema>;

export const AdminUpdateProductRequestSchema = z
  .object({
    name: z.string().trim().min(1).max(200).optional(),
    billingType: z.enum(['one_time', 'subscription', 'credits']).optional(),
    entitlementPolicy: z.enum(['snapshot', 'all_apps_access']).optional(),
    expectedUpdatedAt: IsoDateTimeSchema,
    reason: AdminDraftReasonSchema,
  })
  .strict()
  .refine(
    (value) =>
      value.name !== undefined ||
      value.billingType !== undefined ||
      value.entitlementPolicy !== undefined,
    {
      message: 'At least one product draft field is required',
    },
  );
export type AdminUpdateProductRequest = z.infer<typeof AdminUpdateProductRequestSchema>;

export const AdminCreateProductVersionRequestSchema = z
  .object({
    version: z.number().int().positive(),
    accessDurationDays: z.number().int().positive().optional().nullable(),
    salesTerms: AdminMetadataSchema.optional(),
    reason: AdminDraftReasonSchema,
  })
  .strict();
export type AdminCreateProductVersionRequest = z.infer<
  typeof AdminCreateProductVersionRequestSchema
>;

export const AdminUpdateProductVersionRequestSchema = z
  .object({
    accessDurationDays: z.number().int().positive().optional().nullable(),
    salesTerms: AdminMetadataSchema.optional(),
    reason: AdminDraftReasonSchema,
  })
  .strict()
  .refine((value) => value.accessDurationDays !== undefined || value.salesTerms !== undefined, {
    message: 'At least one product version draft field is required',
  });
export type AdminUpdateProductVersionRequest = z.infer<
  typeof AdminUpdateProductVersionRequestSchema
>;

const AdminPriceFieldsSchema = z.object({
  currency: z
    .string()
    .regex(/^[A-Z]{3}$/)
    .optional(),
  amountMinor: z.number().int().nonnegative().optional(),
  channel: z
    .string()
    .regex(/^(?:manual|redemption|[a-z0-9]+(?:[_-][a-z0-9]+)*)$/)
    .optional(),
  externalPriceId: z.string().trim().min(1).nullable().optional(),
  validFrom: IsoDateTimeSchema.optional(),
  validUntil: IsoDateTimeSchema.nullable().optional(),
});

export const AdminCreatePriceRequestSchema = AdminPriceFieldsSchema.extend({
  currency: z.string().regex(/^[A-Z]{3}$/),
  amountMinor: z.number().int().nonnegative(),
  channel: z.string().regex(/^(?:manual|redemption|[a-z0-9]+(?:[_-][a-z0-9]+)*)$/),
  reason: AdminDraftReasonSchema,
}).strict();
export type AdminCreatePriceRequest = z.infer<typeof AdminCreatePriceRequestSchema>;

export const AdminUpdatePriceRequestSchema = AdminPriceFieldsSchema.extend({
  expectedUpdatedAt: IsoDateTimeSchema,
  reason: AdminDraftReasonSchema,
})
  .strict()
  .refine(
    (value) => Object.keys(value).some((key) => !['expectedUpdatedAt', 'reason'].includes(key)),
    {
      message: 'At least one price draft field is required',
    },
  );
export type AdminUpdatePriceRequest = z.infer<typeof AdminUpdatePriceRequestSchema>;

export const AdminProductSummarySchema = z
  .object({
    id: UuidSchema,
    sku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    name: z.string().min(1).max(200),
    billingType: z.enum(['one_time', 'subscription', 'credits']),
    status: z.enum(['draft', 'active', 'archived']),
    currentVersion: z
      .object({
        id: UuidSchema,
        version: z.number().int().positive(),
        status: z.literal('published'),
      })
      .strict()
      .nullable(),
  })
  .strict();
export type AdminProductSummary = z.infer<typeof AdminProductSummarySchema>;

export const AdminProductListResponseSchema = z
  .object({ items: z.array(AdminProductSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminProductListResponse = z.infer<typeof AdminProductListResponseSchema>;

export const AdminProductVersionSummarySchema = z
  .object({
    id: UuidSchema,
    productId: UuidSchema,
    productSku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    version: z.number().int().positive(),
    status: z.enum(['draft', 'published', 'retired']),
    publishedAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type AdminProductVersionSummary = z.infer<typeof AdminProductVersionSummarySchema>;

export const AdminProductVersionListResponseSchema = z
  .object({ items: z.array(AdminProductVersionSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminProductVersionListResponse = z.infer<typeof AdminProductVersionListResponseSchema>;

export const AdminRedemptionBatchSummarySchema = z
  .object({
    id: UuidSchema,
    name: z.string().min(1).max(200),
    productSku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    productVersion: z.number().int().positive(),
    status: z.enum(['draft', 'active', 'paused', 'closed']),
    codePrefix: z.string().regex(/^[A-Z0-9]+(?:-[A-Z0-9]+)*$/),
    quantity: z.number().int().positive(),
    issuedCount: z.number().int().nonnegative(),
    redeemedCount: z.number().int().nonnegative(),
    startsAt: IsoDateTimeSchema,
    expiresAt: IsoDateTimeSchema.nullable(),
    createdAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminRedemptionBatchSummary = z.infer<typeof AdminRedemptionBatchSummarySchema>;

export const AdminRedemptionBatchListResponseSchema = z
  .object({ items: z.array(AdminRedemptionBatchSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminRedemptionBatchListResponse = z.infer<
  typeof AdminRedemptionBatchListResponseSchema
>;

export const AdminRedemptionCodeSummarySchema = z
  .object({
    id: UuidSchema,
    batchId: UuidSchema,
    codeHint: z.string().min(1).max(200),
    status: z.enum(['issued', 'redeemed', 'revoked']),
    redeemedAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type AdminRedemptionCodeSummary = z.infer<typeof AdminRedemptionCodeSummarySchema>;

export const AdminRedemptionCodeListResponseSchema = z
  .object({ items: z.array(AdminRedemptionCodeSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminRedemptionCodeListResponse = z.infer<typeof AdminRedemptionCodeListResponseSchema>;

export const AdminRedemptionSummarySchema = z
  .object({
    id: UuidSchema,
    batchId: UuidSchema,
    userId: UserIdSchema,
    productSku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    status: z.literal('redeemed'),
    redeemedAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminRedemptionSummary = z.infer<typeof AdminRedemptionSummarySchema>;

export const AdminRedemptionListResponseSchema = z
  .object({ items: z.array(AdminRedemptionSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminRedemptionListResponse = z.infer<typeof AdminRedemptionListResponseSchema>;

export const AdminOriginSummarySchema = z
  .object({
    id: UuidSchema,
    appId: UuidSchema,
    appSlug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
    environment: z.enum(['development', 'staging', 'production']),
    origin: z.string().url(),
    isActive: z.boolean(),
    createdAt: IsoDateTimeSchema,
    updatedAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminOriginSummary = z.infer<typeof AdminOriginSummarySchema>;

export const AdminOriginListResponseSchema = z
  .object({ items: z.array(AdminOriginSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminOriginListResponse = z.infer<typeof AdminOriginListResponseSchema>;

export const AdminFeatureSummarySchema = z
  .object({
    id: UuidSchema,
    appSlug: z
      .string()
      .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
      .nullable(),
    code: z.string().min(1),
    name: z.string().min(1).max(200),
    valueType: z.enum(['boolean', 'integer', 'string', 'json']),
    status: z.enum(['active', 'retired']),
    mergeStrategy: z.enum(['any_true', 'sum', 'max', 'min', 'latest']),
    createdAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminFeatureSummary = z.infer<typeof AdminFeatureSummarySchema>;

export const AdminFeatureListResponseSchema = z
  .object({ items: z.array(AdminFeatureSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminFeatureListResponse = z.infer<typeof AdminFeatureListResponseSchema>;

export const AdminPriceSummarySchema = z
  .object({
    id: UuidSchema,
    productId: UuidSchema,
    productSku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    productVersion: z.number().int().positive(),
    currency: z.string().regex(/^[A-Z]{3}$/),
    amountMinor: z.number().int().nonnegative(),
    channel: z.string().min(1),
    externalPriceId: z.string().nullable(),
    status: z.enum(['draft', 'active', 'retired']),
    validFrom: IsoDateTimeSchema,
    validUntil: IsoDateTimeSchema.nullable(),
    createdAt: IsoDateTimeSchema,
    updatedAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminPriceSummary = z.infer<typeof AdminPriceSummarySchema>;

export const AdminPriceListResponseSchema = z
  .object({ items: z.array(AdminPriceSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminPriceListResponse = z.infer<typeof AdminPriceListResponseSchema>;

export const AdminFeatureSnapshotSchema = z
  .object({ featureCode: z.string().min(1), value: z.unknown() })
  .strict();
export type AdminFeatureSnapshot = z.infer<typeof AdminFeatureSnapshotSchema>;

export const AdminProductOverviewSchema = z
  .object({
    product: AdminProductSummarySchema,
    versions: z.array(AdminProductVersionSummarySchema),
    prices: z.array(AdminPriceSummarySchema),
    featureSnapshots: z.array(AdminFeatureSnapshotSchema),
    redemptionBatches: z.array(AdminRedemptionBatchSummarySchema),
    auditLogs: z.array(AdminAuditLogSummarySchema),
  })
  .strict();
export type AdminProductOverview = z.infer<typeof AdminProductOverviewSchema>;

export const AdminCommandMetadataSchema = z
  .object({
    reason: z.string().trim().min(1).max(1000),
    confirmation: z.literal(true),
  })
  .strict();
export type AdminCommandMetadata = z.infer<typeof AdminCommandMetadataSchema>;

export const AdminPublishProductVersionRequestSchema = AdminCommandMetadataSchema;
export type AdminPublishProductVersionRequest = z.infer<
  typeof AdminPublishProductVersionRequestSchema
>;

export const AdminRetireProductVersionRequestSchema = AdminCommandMetadataSchema;
export type AdminRetireProductVersionRequest = z.infer<
  typeof AdminRetireProductVersionRequestSchema
>;

export const AdminSetCurrentProductVersionRequestSchema = AdminCommandMetadataSchema.extend({
  productVersionId: UuidSchema,
}).strict();
export type AdminSetCurrentProductVersionRequest = z.infer<
  typeof AdminSetCurrentProductVersionRequestSchema
>;

export const AdminGenerateRedemptionCodesRequestSchema = AdminCommandMetadataSchema.extend({
  quantity: z.number().int().min(1).max(10_000),
}).strict();
export type AdminGenerateRedemptionCodesRequest = z.infer<
  typeof AdminGenerateRedemptionCodesRequestSchema
>;

export const AdminPauseRedemptionBatchRequestSchema = AdminCommandMetadataSchema;
export type AdminPauseRedemptionBatchRequest = z.infer<
  typeof AdminPauseRedemptionBatchRequestSchema
>;

export const AdminCloseRedemptionBatchRequestSchema = AdminCommandMetadataSchema;
export type AdminCloseRedemptionBatchRequest = z.infer<
  typeof AdminCloseRedemptionBatchRequestSchema
>;

export const AdminGeneratedRedemptionCodeSchema = z
  .object({ code: z.string().min(1).max(512), codeHint: z.string().min(1).max(200) })
  .strict();
export type AdminGeneratedRedemptionCode = z.infer<typeof AdminGeneratedRedemptionCodeSchema>;

export const AdminGenerateRedemptionCodesResponseSchema = z
  .object({
    batchId: UuidSchema,
    codes: z.array(AdminGeneratedRedemptionCodeSchema).min(1).max(10_000),
  })
  .strict();
export type AdminGenerateRedemptionCodesResponse = z.infer<
  typeof AdminGenerateRedemptionCodesResponseSchema
>;

export const AdminProductVersionCommandResponseSchema = z
  .object({
    productVersionId: UuidSchema,
    status: z.enum(['published', 'retired']),
    publishedAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type AdminProductVersionCommandResponse = z.infer<
  typeof AdminProductVersionCommandResponseSchema
>;

export const AdminRedemptionBatchCommandResponseSchema = z
  .object({ batchId: UuidSchema, status: z.enum(['paused', 'closed']) })
  .strict();
export type AdminRedemptionBatchCommandResponse = z.infer<
  typeof AdminRedemptionBatchCommandResponseSchema
>;
