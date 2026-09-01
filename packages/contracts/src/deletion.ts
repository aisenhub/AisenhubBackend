import { z } from 'zod';

import { IsoDateTimeSchema, UserIdSchema } from './identity';

export const AccountDeletionStatusSchema = z.enum([
  'pending',
  'processing',
  'completed',
  'failed',
  'cancelled',
]);
export type AccountDeletionStatus = z.infer<typeof AccountDeletionStatusSchema>;

export const AccountDeletionRequestSchema = z
  .object({
    deletionRequestId: UserIdSchema,
    status: AccountDeletionStatusSchema,
    executeAfter: IsoDateTimeSchema,
    requestedAt: IsoDateTimeSchema,
    completedAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type AccountDeletionRequest = z.infer<typeof AccountDeletionRequestSchema>;

export const CreateAccountDeletionRequestSchema = z.object({}).strict();
export type CreateAccountDeletionRequest = z.infer<typeof CreateAccountDeletionRequestSchema>;
