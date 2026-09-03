import { z } from 'zod';

import {
  ApplicationMembershipCommandResponseSchema,
  OAuthClientBindingSummarySchema,
} from './application-membership';
import { IsoDateTimeSchema, UserIdSchema } from './identity';

const UuidSchema = z.string().uuid();
const AdminCommandMetadataSchema = z
  .object({ reason: z.string().trim().min(1).max(1000), confirmation: z.literal(true) })
  .strict();

export const AdminApplicationMembershipSummarySchema = z
  .object({
    id: UuidSchema,
    applicationId: UuidSchema,
    applicationSlug: z.string().min(1).max(100),
    applicationName: z.string().min(1).max(200),
    userId: UserIdSchema,
    status: z.enum(['pending', 'active', 'suspended', 'left', 'deleted']),
    createdSource: z.string().min(1).max(100),
    joinedAt: IsoDateTimeSchema,
    activatedAt: IsoDateTimeSchema.nullable(),
    suspendedAt: IsoDateTimeSchema.nullable(),
    suspendedReason: z.string().nullable(),
    leftAt: IsoDateTimeSchema.nullable(),
    deletedAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type AdminApplicationMembershipSummary = z.infer<
  typeof AdminApplicationMembershipSummarySchema
>;

export const AdminApplicationMembershipListResponseSchema = z
  .object({ items: z.array(AdminApplicationMembershipSummarySchema) })
  .strict();
export type AdminApplicationMembershipListResponse = z.infer<
  typeof AdminApplicationMembershipListResponseSchema
>;

export const AdminCreateApplicationMembershipRequestSchema = AdminCommandMetadataSchema.extend({
  userId: UserIdSchema,
  createdSource: z.string().trim().min(1).max(100).default('admin'),
}).strict();
export type AdminCreateApplicationMembershipRequest = z.infer<
  typeof AdminCreateApplicationMembershipRequestSchema
>;

export const AdminApplicationMembershipLifecycleRequestSchema = AdminCommandMetadataSchema;
export type AdminApplicationMembershipLifecycleRequest = z.infer<
  typeof AdminApplicationMembershipLifecycleRequestSchema
>;

export const AdminCreateOAuthClientRequestSchema = AdminCommandMetadataSchema.extend({
  provider: z.string().trim().min(1).max(100),
  externalClientId: z.string().trim().min(1).max(255),
  clientType: z.enum(['public', 'confidential']),
  environment: z.enum(['development', 'staging', 'production']),
  name: z.string().trim().min(1).max(200),
}).strict();
export type AdminCreateOAuthClientRequest = z.infer<typeof AdminCreateOAuthClientRequestSchema>;

export const AdminOAuthClientLifecycleRequestSchema = AdminCommandMetadataSchema;
export type AdminOAuthClientLifecycleRequest = z.infer<
  typeof AdminOAuthClientLifecycleRequestSchema
>;

export const AdminOAuthClientCommandResponseSchema = OAuthClientBindingSummarySchema.extend({
  auditLogId: UuidSchema,
}).strict();
export type AdminOAuthClientCommandResponse = z.infer<typeof AdminOAuthClientCommandResponseSchema>;

export { ApplicationMembershipCommandResponseSchema };
