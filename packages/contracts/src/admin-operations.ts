import { z } from 'zod';

import { IsoDateTimeSchema, UserIdSchema } from './identity';
import { PageMetaSchema } from './pagination';

const UuidSchema = z.string().uuid();
const JsonObjectSchema = z.record(z.string(), z.unknown());

export const AdminApplicationSummarySchema = z
  .object({
    id: UuidSchema,
    slug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
    name: z.string().min(1).max(200),
    category: z.string().min(1).max(100),
    status: z.enum(['draft', 'active', 'suspended', 'retired']),
    originCount: z.number().int().nonnegative(),
    createdAt: IsoDateTimeSchema,
    updatedAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminApplicationSummary = z.infer<typeof AdminApplicationSummarySchema>;

export const AdminApplicationListResponseSchema = z
  .object({ items: z.array(AdminApplicationSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminApplicationListResponse = z.infer<typeof AdminApplicationListResponseSchema>;

export const AdminUserSummarySchema = z
  .object({
    id: UserIdSchema,
    displayName: z.string().nullable(),
    status: z.enum(['active', 'disabled', 'deletion_pending', 'deleted']),
    adminRole: z.enum(['owner', 'admin', 'support', 'finance']).nullable(),
    createdAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminUserSummary = z.infer<typeof AdminUserSummarySchema>;

export const AdminUserListResponseSchema = z
  .object({ items: z.array(AdminUserSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminUserListResponse = z.infer<typeof AdminUserListResponseSchema>;

export const AdminEntitlementSummarySchema = z
  .object({
    id: UuidSchema,
    userId: UserIdSchema,
    displayName: z.string().nullable(),
    productSku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    productVersion: z.number().int().positive(),
    sourceType: z.enum(['order_item', 'redemption', 'admin', 'promotion', 'admin_restore']),
    status: z.enum(['active', 'revoked']),
    startsAt: IsoDateTimeSchema,
    expiresAt: IsoDateTimeSchema.nullable(),
    createdAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminEntitlementSummary = z.infer<typeof AdminEntitlementSummarySchema>;

export const AdminEntitlementListResponseSchema = z
  .object({ items: z.array(AdminEntitlementSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminEntitlementListResponse = z.infer<typeof AdminEntitlementListResponseSchema>;

export const AdminFeedbackSummarySchema = z
  .object({
    id: UuidSchema,
    appSlug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
    userId: UserIdSchema,
    kind: z.string().min(1).max(50),
    title: z.string().min(1).max(200),
    content: z.string().nullable(),
    status: z.enum(['open', 'in_progress', 'resolved', 'closed']),
    createdAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminFeedbackSummary = z.infer<typeof AdminFeedbackSummarySchema>;

export const AdminFeedbackListResponseSchema = z
  .object({ items: z.array(AdminFeedbackSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminFeedbackListResponse = z.infer<typeof AdminFeedbackListResponseSchema>;

export const AdminAuditLogSummarySchema = z
  .object({
    id: UuidSchema,
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
export type AdminAuditLogSummary = z.infer<typeof AdminAuditLogSummarySchema>;

export const AdminAuditLogListResponseSchema = z
  .object({ items: z.array(AdminAuditLogSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminAuditLogListResponse = z.infer<typeof AdminAuditLogListResponseSchema>;

export const AdminSystemHealthCheckSchema = z
  .object({ name: z.string().min(1), status: z.enum(['healthy', 'degraded', 'unavailable']) })
  .strict();
export type AdminSystemHealthCheck = z.infer<typeof AdminSystemHealthCheckSchema>;

export const AdminSystemHealthResponseSchema = z
  .object({
    status: z.enum(['healthy', 'degraded', 'unavailable']),
    checks: z.array(AdminSystemHealthCheckSchema).min(1),
  })
  .strict();
export type AdminSystemHealthResponse = z.infer<typeof AdminSystemHealthResponseSchema>;
