import { z } from 'zod';

export const UserIdSchema = z.string().uuid();
export type UserId = z.infer<typeof UserIdSchema>;

export const IsoDateTimeSchema = z.string().datetime({ offset: true });

export const ProfileStatusSchema = z.enum(['active', 'disabled', 'deletion_pending', 'deleted']);
export type ProfileStatus = z.infer<typeof ProfileStatusSchema>;

export const ProfileIdentitySchema = z
  .object({
    userId: UserIdSchema,
    displayName: z.string().min(1).max(200).nullable(),
    avatarUrl: z.string().url().max(2048).nullable(),
    locale: z
      .string()
      .regex(/^[A-Za-z]{2}(-[A-Za-z0-9]{2,8})?$/)
      .nullable(),
    status: ProfileStatusSchema,
  })
  .strict();
export type ProfileIdentity = z.infer<typeof ProfileIdentitySchema>;

export const SessionExchangeRequestSchema = z.object({}).strict();
export type SessionExchangeRequest = z.infer<typeof SessionExchangeRequestSchema>;

export const SessionExchangeResponseSchema = z
  .object({
    authenticated: z.literal(true),
    identity: ProfileIdentitySchema,
    expiresAt: IsoDateTimeSchema,
    csrfToken: z.string().min(1).max(512),
  })
  .strict();
export type SessionExchangeResponse = z.infer<typeof SessionExchangeResponseSchema>;

export const AuthenticatedSessionSchema = z
  .object({
    authenticated: z.literal(true),
    identity: ProfileIdentitySchema,
    expiresAt: IsoDateTimeSchema,
    csrfToken: z.string().min(1).max(512).optional(),
  })
  .strict();

export const AnonymousSessionSchema = z
  .object({
    authenticated: z.literal(false),
    identity: z.null(),
    expiresAt: z.null(),
  })
  .strict();

export const SessionResponseSchema = z.discriminatedUnion('authenticated', [
  AuthenticatedSessionSchema,
  AnonymousSessionSchema,
]);
export type SessionResponse = z.infer<typeof SessionResponseSchema>;

export const SessionDeleteResponseSchema = z
  .object({
    revoked: z.literal(true),
  })
  .strict();
export type SessionDeleteResponse = z.infer<typeof SessionDeleteResponseSchema>;

export const MeResponseSchema = z
  .object({
    profile: ProfileIdentitySchema,
  })
  .strict();
export type MeResponse = z.infer<typeof MeResponseSchema>;

export const AdminAalSchema = z.enum(['aal1', 'aal2']);
export type AdminAal = z.infer<typeof AdminAalSchema>;

export const AdminMfaStateSchema = z.enum(['not_required', 'required', 'verified']);
export type AdminMfaState = z.infer<typeof AdminMfaStateSchema>;

export const AdminSessionResponseSchema = z
  .object({
    authenticated: z.literal(true),
    identity: ProfileIdentitySchema.pick({ userId: true, displayName: true }),
    role: z.enum(['owner', 'admin', 'support', 'finance']),
    aal: AdminAalSchema,
    mfaState: AdminMfaStateSchema,
    expiresAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminSessionResponse = z.infer<typeof AdminSessionResponseSchema>;

export const ApplicationIdentitySchema = z
  .object({
    slug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
    name: z.string().min(1).max(200),
    category: z.string().min(1).max(100),
    status: z.enum(['draft', 'active', 'suspended', 'retired']),
  })
  .strict();
export type ApplicationIdentity = z.infer<typeof ApplicationIdentitySchema>;
