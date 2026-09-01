import { z } from 'zod';

export const PublicProductSchema = z
  .object({
    sku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    name: z.string().min(1).max(200),
    billingType: z.enum(['one_time', 'subscription', 'credits']),
    version: z.number().int().positive(),
  })
  .strict();
export type PublicProduct = z.infer<typeof PublicProductSchema>;

export const PublicProductsResponseSchema = z
  .object({ products: z.array(PublicProductSchema) })
  .strict();
export type PublicProductsResponse = z.infer<typeof PublicProductsResponseSchema>;

export const AccessResponseSchema = z
  .object({
    allowed: z.boolean(),
    feature: z.string().min(1),
    value: z.unknown().nullable(),
    sourceProduct: z.string().nullable(),
    expiresAt: z.string().datetime({ offset: true }).nullable(),
    decisionId: z.string().uuid(),
  })
  .strict();
export type AccessResponse = z.infer<typeof AccessResponseSchema>;

export const EntitlementSummarySchema = z
  .object({
    feature: z.string().min(1),
    value: z.unknown(),
    sourceProduct: z.string().min(1),
    expiresAt: z.string().datetime({ offset: true }).nullable(),
  })
  .strict();
export type EntitlementSummary = z.infer<typeof EntitlementSummarySchema>;

export const EntitlementsResponseSchema = z
  .object({ entitlements: z.array(EntitlementSummarySchema) })
  .strict();
export type EntitlementsResponse = z.infer<typeof EntitlementsResponseSchema>;

export const RedemptionRequestSchema = z.object({ code: z.string().min(1).max(512) }).strict();
export type RedemptionRequest = z.infer<typeof RedemptionRequestSchema>;

export const RedemptionResponseSchema = z
  .object({
    redemptionId: z.string().uuid(),
    grantId: z.string().uuid(),
    status: z.literal('redeemed'),
  })
  .strict();
export type RedemptionResponse = z.infer<typeof RedemptionResponseSchema>;

export const FeedbackRequestSchema = z
  .object({
    kind: z.string().min(1).max(50),
    title: z.string().min(1).max(200),
    content: z.string().min(1).max(20_000),
  })
  .strict();
export type FeedbackRequest = z.infer<typeof FeedbackRequestSchema>;

export const FeedbackResponseSchema = z
  .object({
    id: z.string().uuid(),
    status: z.enum(['open', 'in_progress', 'resolved', 'closed']),
    createdAt: z.string().datetime({ offset: true }),
  })
  .strict();
export type FeedbackResponse = z.infer<typeof FeedbackResponseSchema>;
