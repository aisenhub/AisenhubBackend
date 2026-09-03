import { z } from 'zod';

import { IsoDateTimeSchema, UserIdSchema } from './identity';

const UuidSchema = z.string().uuid();

const AdminCommandMetadataSchema = z
  .object({
    reason: z.string().trim().min(1).max(1000),
    confirmation: z.literal(true),
  })
  .strict();

export const AdminGrantEntitlementRequestSchema = AdminCommandMetadataSchema.extend({
  productVersionId: UuidSchema,
  startsAt: IsoDateTimeSchema.optional(),
  expiresAt: IsoDateTimeSchema.nullable().optional(),
}).strict();
export type AdminGrantEntitlementRequest = z.infer<typeof AdminGrantEntitlementRequestSchema>;

export const AdminRevokeEntitlementRequestSchema = AdminCommandMetadataSchema;
export type AdminRevokeEntitlementRequest = z.infer<typeof AdminRevokeEntitlementRequestSchema>;

export const AdminRestoreEntitlementRequestSchema = AdminCommandMetadataSchema;
export type AdminRestoreEntitlementRequest = z.infer<typeof AdminRestoreEntitlementRequestSchema>;

export const AdminDisableUserRequestSchema = AdminCommandMetadataSchema;
export type AdminDisableUserRequest = z.infer<typeof AdminDisableUserRequestSchema>;

export const AdminProcessDeletionRequestSchema = AdminCommandMetadataSchema;
export type AdminProcessDeletionRequest = z.infer<typeof AdminProcessDeletionRequestSchema>;

export const AdminGrantedEntitlementCommandResponseSchema = z
  .object({
    grantId: UuidSchema,
    sourceId: UuidSchema,
    status: z.literal('active'),
    startsAt: IsoDateTimeSchema,
    expiresAt: IsoDateTimeSchema.nullable(),
    auditLogId: UuidSchema,
  })
  .strict();
export type AdminGrantedEntitlementCommandResponse = z.infer<
  typeof AdminGrantedEntitlementCommandResponseSchema
>;

export const AdminRevokedEntitlementCommandResponseSchema = z
  .object({
    grantId: UuidSchema,
    status: z.literal('revoked'),
    revokedAt: IsoDateTimeSchema,
    auditLogId: UuidSchema,
  })
  .strict();
export type AdminRevokedEntitlementCommandResponse = z.infer<
  typeof AdminRevokedEntitlementCommandResponseSchema
>;

export const AdminRestoredEntitlementCommandResponseSchema =
  AdminGrantedEntitlementCommandResponseSchema.extend({
    restoredGrantId: UuidSchema,
    restoresGrantId: UuidSchema,
  }).strict();
export type AdminRestoredEntitlementCommandResponse = z.infer<
  typeof AdminRestoredEntitlementCommandResponseSchema
>;

export const AdminDisabledUserCommandResponseSchema = z
  .object({
    userId: UserIdSchema,
    status: z.literal('disabled'),
    auditLogId: UuidSchema,
  })
  .strict();
export type AdminDisabledUserCommandResponse = z.infer<
  typeof AdminDisabledUserCommandResponseSchema
>;

export const AdminProcessedDeletionCommandResponseSchema = z
  .object({
    deletionRequestId: UuidSchema,
    userId: UserIdSchema,
    status: z.literal('processing'),
    attemptCount: z.number().int().positive(),
    processingStartedAt: IsoDateTimeSchema,
    auditLogId: UuidSchema,
  })
  .strict();
export type AdminProcessedDeletionCommandResponse = z.infer<
  typeof AdminProcessedDeletionCommandResponseSchema
>;
