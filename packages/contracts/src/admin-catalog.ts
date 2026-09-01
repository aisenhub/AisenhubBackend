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
