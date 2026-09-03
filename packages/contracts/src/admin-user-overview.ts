import { z } from 'zod';

import { IsoDateTimeSchema, ProfileStatusSchema, UserIdSchema } from './identity';
import { PageMetaSchema } from './pagination';

const UuidSchema = z.string().uuid();
const JsonObjectSchema = z.record(z.string(), z.unknown());

export const AdminAccountDeletionRequestSummarySchema = z
  .object({
    id: UuidSchema,
    userId: UserIdSchema,
    status: z.enum(['pending', 'processing', 'completed', 'failed', 'cancelled']),
    executeAfter: IsoDateTimeSchema,
    attemptCount: z.number().int().nonnegative(),
    lastErrorCode: z
      .string()
      .regex(/^[A-Z][A-Z0-9_]{1,63}$/)
      .nullable(),
    nextAttemptAt: IsoDateTimeSchema.nullable(),
    requestedAt: IsoDateTimeSchema,
    completedAt: IsoDateTimeSchema.nullable(),
    cancelledAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type AdminAccountDeletionRequestSummary = z.infer<
  typeof AdminAccountDeletionRequestSummarySchema
>;

export const AdminAccountDeletionRequestListResponseSchema = z
  .object({
    items: z.array(AdminAccountDeletionRequestSummarySchema),
    page: PageMetaSchema,
  })
  .strict();
export type AdminAccountDeletionRequestListResponse = z.infer<
  typeof AdminAccountDeletionRequestListResponseSchema
>;

export const AdminUserOverviewProfileSchema = z
  .object({
    userId: UserIdSchema,
    displayName: z.string().nullable(),
    avatarUrl: z.string().url().nullable(),
    locale: z.string().nullable(),
    status: ProfileStatusSchema,
    createdAt: IsoDateTimeSchema,
    updatedAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminUserOverviewProfile = z.infer<typeof AdminUserOverviewProfileSchema>;

export const AdminUserOverviewEntitlementSchema = z
  .object({
    id: UuidSchema,
    userId: UserIdSchema,
    productSku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    productVersion: z.number().int().positive(),
    sourceType: z.enum(['order_item', 'redemption', 'admin', 'promotion', 'admin_restore']),
    status: z.enum(['active', 'revoked']),
    startsAt: IsoDateTimeSchema,
    expiresAt: IsoDateTimeSchema.nullable(),
    createdAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminUserOverviewEntitlement = z.infer<typeof AdminUserOverviewEntitlementSchema>;

export const AdminUserOverviewRedemptionSchema = z
  .object({
    id: UuidSchema,
    batchId: UuidSchema,
    userId: UserIdSchema,
    productSku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    status: z.literal('redeemed'),
    redeemedAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminUserOverviewRedemption = z.infer<typeof AdminUserOverviewRedemptionSchema>;

export const AdminUserOverviewFeedbackSchema = z
  .object({
    id: UuidSchema,
    appSlug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
    kind: z.string().min(1).max(50),
    title: z.string().min(1).max(200),
    content: z.string().nullable(),
    status: z.enum(['open', 'in_progress', 'resolved', 'closed']),
    createdAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminUserOverviewFeedback = z.infer<typeof AdminUserOverviewFeedbackSchema>;

export const AdminUserSessionSummarySchema = z
  .object({
    activeCount: z.number().int().nonnegative(),
    totalCount: z.number().int().nonnegative(),
    lastSeenAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type AdminUserSessionSummary = z.infer<typeof AdminUserSessionSummarySchema>;

export const AdminUserOverviewAuditEventSchema = z
  .object({
    id: UuidSchema,
    applicationId: UuidSchema.nullable().default(null),
    actorType: z.enum(['admin', 'system', 'user', 'webhook']),
    actorId: UserIdSchema.nullable(),
    action: z.string().min(1),
    targetType: z.string().min(1),
    targetId: UuidSchema,
    requestId: UuidSchema.nullable(),
    reason: z.string().min(1),
    beforeSummary: JsonObjectSchema,
    afterSummary: JsonObjectSchema,
    createdAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminUserOverviewAuditEvent = z.infer<typeof AdminUserOverviewAuditEventSchema>;

export const AdminUserOverviewSchema = z
  .object({
    profile: AdminUserOverviewProfileSchema,
    adminRole: z.enum(['owner', 'admin', 'support', 'finance']).nullable(),
    entitlements: z.array(AdminUserOverviewEntitlementSchema),
    redemptions: z.array(AdminUserOverviewRedemptionSchema),
    feedback: z.array(AdminUserOverviewFeedbackSchema),
    sessionSummary: AdminUserSessionSummarySchema,
    deletionRequests: z.array(AdminAccountDeletionRequestSummarySchema),
    auditTimeline: z.array(AdminUserOverviewAuditEventSchema),
  })
  .strict();
export type AdminUserOverview = z.infer<typeof AdminUserOverviewSchema>;
