import { z } from 'zod';

export const PaginationQuerySchema = z.object({
  cursor: z.string().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(25),
  search: z.string().min(1).max(200).optional(),
});
export type PaginationQuery = z.infer<typeof PaginationQuerySchema>;

export const PageMetaSchema = z.object({
  hasMore: z.boolean(),
  nextCursor: z.string().min(1).nullable(),
});
export type PageMeta = z.infer<typeof PageMetaSchema>;
