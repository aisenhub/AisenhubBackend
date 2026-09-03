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

export const MeResponseSchema = z
  .object({
    profile: ProfileIdentitySchema,
  })
  .strict();
export type MeResponse = z.infer<typeof MeResponseSchema>;

export const ApplicationContextResponseSchema = z
  .object({
    userId: UserIdSchema,
    clientId: z.string().min(1).max(255),
    application: z
      .object({
        id: z.string().uuid(),
        slug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
      })
      .strict(),
    membershipId: z.string().uuid(),
    membershipStatus: z.literal('active'),
    aal: z.string().min(1).max(32).nullable(),
  })
  .strict();
export type ApplicationContextResponse = z.infer<typeof ApplicationContextResponseSchema>;

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
