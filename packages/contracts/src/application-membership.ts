import { z } from 'zod';

import { IsoDateTimeSchema, UserIdSchema } from './identity';

export const ApplicationRegistrationPolicySchema = z.enum([
  'open',
  'invite_only',
  'admin_created',
  'closed',
]);
export type ApplicationRegistrationPolicy = z.infer<typeof ApplicationRegistrationPolicySchema>;

export const ApplicationMembershipPolicySchema = z.enum([
  'explicit',
  'create_on_first_authorization',
  'create_on_verified_purchase',
]);
export type ApplicationMembershipPolicy = z.infer<typeof ApplicationMembershipPolicySchema>;

export const ApplicationMembershipStatusSchema = z.enum([
  'pending',
  'active',
  'suspended',
  'left',
  'deleted',
]);
export type ApplicationMembershipStatus = z.infer<typeof ApplicationMembershipStatusSchema>;

export const ApplicationSummarySchema = z
  .object({
    id: z.string().uuid(),
    slug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
    name: z.string().min(1).max(200),
    category: z.string().min(1).max(100),
    status: z.enum(['draft', 'active', 'suspended', 'retired']),
    registrationPolicy: ApplicationRegistrationPolicySchema,
    membershipPolicy: ApplicationMembershipPolicySchema,
    defaultLocale: z.string().nullable(),
  })
  .strict();
export type ApplicationSummary = z.infer<typeof ApplicationSummarySchema>;

export const ApplicationMembershipSummarySchema = z
  .object({
    id: z.string().uuid(),
    application: ApplicationSummarySchema,
    userId: UserIdSchema,
    status: ApplicationMembershipStatusSchema,
    createdSource: z.string().min(1).max(100),
    joinedAt: IsoDateTimeSchema,
    activatedAt: IsoDateTimeSchema.nullable(),
    suspendedAt: IsoDateTimeSchema.nullable(),
    leftAt: IsoDateTimeSchema.nullable(),
    deletedAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type ApplicationMembershipSummary = z.infer<typeof ApplicationMembershipSummarySchema>;

export const MyApplicationsResponseSchema = z
  .object({ applications: z.array(ApplicationMembershipSummarySchema) })
  .strict();
export type MyApplicationsResponse = z.infer<typeof MyApplicationsResponseSchema>;

export const ApplicationMembershipCommandActionSchema = z.enum([
  'create',
  'activate',
  'suspend',
  'restore',
  'leave',
  'delete',
]);
export type ApplicationMembershipCommandAction = z.infer<
  typeof ApplicationMembershipCommandActionSchema
>;

export const ApplicationMembershipCommandRequestSchema = z
  .object({
    action: ApplicationMembershipCommandActionSchema,
    applicationId: z.string().uuid().optional(),
    userId: UserIdSchema.optional(),
    membershipId: z.string().uuid().optional(),
    createdSource: z.string().trim().min(1).max(100).optional(),
    reason: z.string().trim().min(1).max(1000),
    idempotencyKey: z.string().trim().min(1).max(255),
  })
  .strict();
export type ApplicationMembershipCommandRequest = z.infer<
  typeof ApplicationMembershipCommandRequestSchema
>;

export const OAuthClientTypeSchema = z.enum(['public', 'confidential']);
export type OAuthClientType = z.infer<typeof OAuthClientTypeSchema>;

export const OAuthClientEnvironmentSchema = z.enum(['development', 'staging', 'production']);
export type OAuthClientEnvironment = z.infer<typeof OAuthClientEnvironmentSchema>;

export const OAuthClientStatusSchema = z.enum(['active', 'disabled']);
export type OAuthClientStatus = z.infer<typeof OAuthClientStatusSchema>;

export const OAuthClientBindingSummarySchema = z
  .object({
    id: z.string().uuid(),
    applicationId: z.string().uuid(),
    provider: z.string().min(1).max(100),
    externalClientId: z.string().min(1).max(255),
    clientType: OAuthClientTypeSchema,
    environment: OAuthClientEnvironmentSchema,
    name: z.string().min(1).max(200),
    status: OAuthClientStatusSchema,
    createdAt: IsoDateTimeSchema,
    updatedAt: IsoDateTimeSchema,
  })
  .strict();
export type OAuthClientBindingSummary = z.infer<typeof OAuthClientBindingSummarySchema>;

export const OAuthClientBindingListResponseSchema = z
  .object({ items: z.array(OAuthClientBindingSummarySchema) })
  .strict();
export type OAuthClientBindingListResponse = z.infer<typeof OAuthClientBindingListResponseSchema>;
