import { z } from 'zod';

import { IsoDateTimeSchema, UserIdSchema } from './identity';
import { PageMetaSchema } from './pagination';

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
