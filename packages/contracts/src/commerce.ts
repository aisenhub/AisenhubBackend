import { z } from 'zod';

import { IsoDateTimeSchema, UserIdSchema } from './identity';
import { PageMetaSchema } from './pagination';

const UuidSchema = z.string().uuid();
const MoneyMinorSchema = z.number().int().nonnegative().safe();
const CurrencySchema = z.string().regex(/^[A-Z]{3}$/);
const JsonObjectSchema = z.record(z.string(), z.unknown());

export const OrderStatusSchema = z.enum([
  'pending',
  'paid',
  'fulfilled',
  'cancelled',
  'partially_refunded',
  'refunded',
  'chargeback',
]);
export type OrderStatus = z.infer<typeof OrderStatusSchema>;

export const PaymentStatusSchema = z.enum([
  'pending',
  'succeeded',
  'partially_refunded',
  'refunded',
  'disputed',
  'failed',
]);
export type PaymentStatus = z.infer<typeof PaymentStatusSchema>;

export const PaymentEventStatusSchema = z.enum(['received', 'processed', 'ignored', 'failed']);
export type PaymentEventStatus = z.infer<typeof PaymentEventStatusSchema>;

export const OrderItemFulfillmentStatusSchema = z.enum(['pending', 'granted', 'revoked']);
export type OrderItemFulfillmentStatus = z.infer<typeof OrderItemFulfillmentStatusSchema>;

export const OrderSummarySchema = z
  .object({
    id: UuidSchema,
    orderNo: z.string().trim().min(1).max(100),
    status: OrderStatusSchema,
    currency: CurrencySchema,
    amountTotal: MoneyMinorSchema,
    channel: z.string().regex(/^[a-z0-9]+(?:[_-][a-z0-9]+)*$/),
    itemCount: z.number().int().nonnegative(),
    createdAt: IsoDateTimeSchema,
    paidAt: IsoDateTimeSchema.nullable(),
    fulfilledAt: IsoDateTimeSchema.nullable(),
    cancelledAt: IsoDateTimeSchema.nullable(),
    refundedAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type OrderSummary = z.infer<typeof OrderSummarySchema>;

export const OrderItemSummarySchema = z
  .object({
    id: UuidSchema,
    productSku: z.string().regex(/^[A-Z0-9][A-Z0-9_-]*$/),
    productName: z.string().trim().min(1).max(200),
    productVersion: z.number().int().positive(),
    quantity: z.literal(1),
    unitAmount: MoneyMinorSchema,
    totalAmount: MoneyMinorSchema,
    salesTerms: JsonObjectSchema,
    fulfillmentStatus: OrderItemFulfillmentStatusSchema,
    refundedAmount: MoneyMinorSchema,
  })
  .strict();
export type OrderItemSummary = z.infer<typeof OrderItemSummarySchema>;

export const PaymentSummarySchema = z
  .object({
    id: UuidSchema,
    provider: z.string().regex(/^[a-z0-9]+(?:[_-][a-z0-9]+)*$/),
    status: PaymentStatusSchema,
    currency: CurrencySchema,
    amount: MoneyMinorSchema,
    failureCode: z
      .string()
      .regex(/^[A-Z0-9][A-Z0-9_.-]*$/)
      .nullable(),
    paidAt: IsoDateTimeSchema.nullable(),
    refundedAt: IsoDateTimeSchema.nullable(),
    disputedAt: IsoDateTimeSchema.nullable(),
    failedAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type PaymentSummary = z.infer<typeof PaymentSummarySchema>;

export const PaymentEventSummarySchema = z
  .object({
    id: UuidSchema,
    provider: z.string().regex(/^[a-z0-9]+(?:[_-][a-z0-9]+)*$/),
    eventType: z.string().regex(/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/),
    status: PaymentEventStatusSchema,
    currency: CurrencySchema,
    amount: MoneyMinorSchema,
    occurredAt: IsoDateTimeSchema,
    processedAt: IsoDateTimeSchema.nullable(),
  })
  .strict();
export type PaymentEventSummary = z.infer<typeof PaymentEventSummarySchema>;

export const OrderResponseSchema = z
  .object({
    order: OrderSummarySchema,
    items: z.array(OrderItemSummarySchema),
  })
  .strict();
export type OrderResponse = z.infer<typeof OrderResponseSchema>;

export const AdminOrderSummarySchema = OrderSummarySchema.extend({
  userId: UserIdSchema.nullable(),
  customerRef: UuidSchema,
}).strict();
export type AdminOrderSummary = z.infer<typeof AdminOrderSummarySchema>;

export const AdminOrderItemOverviewSchema = OrderItemSummarySchema.extend({
  grantId: UuidSchema.nullable(),
  grantStatus: z.enum(['active', 'revoked']).nullable(),
}).strict();
export type AdminOrderItemOverview = z.infer<typeof AdminOrderItemOverviewSchema>;

export const AdminOrderRefundSchema = z
  .object({
    id: UuidSchema,
    orderId: UuidSchema,
    orderItemId: UuidSchema,
    amountMinor: MoneyMinorSchema,
    mode: z.enum(['compensation', 'return']),
    reason: z.string().min(1).max(1000),
    createdAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminOrderRefund = z.infer<typeof AdminOrderRefundSchema>;

export const AdminOrderExceptionSchema = z
  .object({
    id: UuidSchema,
    orderId: UuidSchema,
    paymentId: UuidSchema,
    paymentEventId: UuidSchema,
    type: z.enum(['late_payment_after_cancel', 'ignored_event']),
    reason: z.string().min(1).max(1000),
    createdAt: IsoDateTimeSchema,
  })
  .strict();
export type AdminOrderException = z.infer<typeof AdminOrderExceptionSchema>;

export const AdminOrderAuditEventSchema = z
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
export type AdminOrderAuditEvent = z.infer<typeof AdminOrderAuditEventSchema>;

export const AdminOrderOverviewSchema = z
  .object({
    order: AdminOrderSummarySchema,
    items: z.array(AdminOrderItemOverviewSchema),
    payments: z.array(PaymentSummarySchema),
    events: z.array(PaymentEventSummarySchema),
    refunds: z.array(AdminOrderRefundSchema),
    exceptions: z.array(AdminOrderExceptionSchema),
    auditTimeline: z.array(AdminOrderAuditEventSchema),
  })
  .strict();
export type AdminOrderOverview = z.infer<typeof AdminOrderOverviewSchema>;

export const AdminOrderListResponseSchema = z
  .object({ items: z.array(AdminOrderSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminOrderListResponse = z.infer<typeof AdminOrderListResponseSchema>;

export const AdminPaymentListResponseSchema = z
  .object({ items: z.array(PaymentSummarySchema), page: PageMetaSchema })
  .strict();
export type AdminPaymentListResponse = z.infer<typeof AdminPaymentListResponseSchema>;

const AdminCommandMetadataSchema = z
  .object({
    reason: z.string().trim().min(1).max(1000),
    confirmation: z.literal(true),
  })
  .strict();

export const AdminVerifyOrderRequestSchema = AdminCommandMetadataSchema.extend({
  paymentReference: z.string().trim().min(1).max(200).regex(/^\S+$/),
  amountMinor: MoneyMinorSchema,
  currency: CurrencySchema,
}).strict();
export type AdminVerifyOrderRequest = z.infer<typeof AdminVerifyOrderRequestSchema>;

export const AdminVerifyOrderResponseSchema = z
  .object({
    orderId: UuidSchema,
    paymentId: UuidSchema,
    paymentEventId: UuidSchema,
    status: z.literal('fulfilled'),
    grantIds: z.array(UuidSchema),
    idempotent: z.boolean(),
    auditLogId: UuidSchema,
    fulfillmentAuditLogId: UuidSchema,
    overviewPath: z.string().regex(/^\/v1\/admin\/orders\/[0-9a-f-]+\/overview$/i),
    auditPath: z.string().regex(/^\/v1\/admin\/audit-logs\/[0-9a-f-]+$/i),
  })
  .strict();
export type AdminVerifyOrderResponse = z.infer<typeof AdminVerifyOrderResponseSchema>;

export const AdminRefundOrderItemRequestSchema = AdminCommandMetadataSchema.extend({
  amountMinor: MoneyMinorSchema.refine((value) => value > 0, 'Refund amount must be positive.'),
  mode: z.enum(['compensation', 'return']),
}).strict();
export type AdminRefundOrderItemRequest = z.infer<typeof AdminRefundOrderItemRequestSchema>;

export const AdminRefundOrderItemResponseSchema = z
  .object({
    itemId: UuidSchema,
    orderId: UuidSchema,
    refundedAmount: MoneyMinorSchema,
    mode: z.enum(['compensation', 'return']),
    orderStatus: z.enum(['partially_refunded', 'refunded']),
    paymentStatus: z.enum(['partially_refunded', 'refunded']),
    grantId: UuidSchema.nullable(),
    domainAuditLogId: UuidSchema,
    auditLogId: UuidSchema,
    idempotent: z.boolean(),
    overviewPath: z.string().regex(/^\/v1\/admin\/orders\/[0-9a-f-]+\/overview$/i),
    auditPath: z.string().regex(/^\/v1\/admin\/audit-logs\/[0-9a-f-]+$/i),
  })
  .strict();
export type AdminRefundOrderItemResponse = z.infer<typeof AdminRefundOrderItemResponseSchema>;

export const AdminChargebackOrderRequestSchema = AdminCommandMetadataSchema;
export type AdminChargebackOrderRequest = z.infer<typeof AdminChargebackOrderRequestSchema>;

const SensitiveSummaryKeys = new Set([
  'authorization',
  'card_number',
  'card_expiry',
  'cvv',
  'cvc',
  'pan',
  'password',
  'secret',
  'token',
  'access_token',
  'refresh_token',
  'payment_method',
  'payment_method_token',
  'credential',
  'credentials',
]);

function hasSensitiveSummaryKey(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(hasSensitiveSummaryKey);
  if (!value || typeof value !== 'object') return false;
  return Object.entries(value).some(
    ([key, child]) => SensitiveSummaryKeys.has(key.toLowerCase()) || hasSensitiveSummaryKey(child),
  );
}

export const PaymentWebhookEventSchema = z
  .object({
    paymentId: UuidSchema,
    orderId: UuidSchema,
    provider: z.string().regex(/^[a-z0-9]+(?:[_-][a-z0-9]+)*$/),
    externalEventId: z.string().trim().min(1).max(200),
    eventType: z.string().regex(/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/),
    currency: CurrencySchema,
    amount: MoneyMinorSchema,
    occurredAt: IsoDateTimeSchema,
    payloadSummary: JsonObjectSchema.refine(
      (value) => JSON.stringify(value).length <= 32768 && !hasSensitiveSummaryKey(value),
      'Webhook payload must be a minimized credential-free summary.',
    ),
  })
  .strict();
export type PaymentWebhookEvent = z.infer<typeof PaymentWebhookEventSchema>;
