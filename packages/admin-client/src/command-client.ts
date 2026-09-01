import {
  AdminDisableUserRequestSchema,
  AdminDisabledUserCommandResponseSchema,
  AdminGrantEntitlementRequestSchema,
  AdminGrantedEntitlementCommandResponseSchema,
  AdminCloseRedemptionBatchRequestSchema,
  AdminChangeProductionOriginRequestSchema,
  AdminCurrentProductVersionCommandResponseSchema,
  AdminCreateRedemptionBatchRequestSchema,
  AdminCreateRedemptionBatchResponseSchema,
  AdminGenerateRedemptionCodesRequestSchema,
  AdminGenerateRedemptionCodesResponseSchema,
  AdminPauseRedemptionBatchRequestSchema,
  AdminProcessDeletionRequestSchema,
  AdminProcessedDeletionCommandResponseSchema,
  AdminProductVersionCommandResponseSchema,
  AdminProductionOriginCommandResponseSchema,
  AdminPublishProductVersionRequestSchema,
  AdminRedemptionBatchCommandResponseSchema,
  AdminRetireProductVersionRequestSchema,
  AdminRestoreEntitlementRequestSchema,
  AdminRestoredEntitlementCommandResponseSchema,
  AdminRevokeEntitlementRequestSchema,
  AdminRevokedEntitlementCommandResponseSchema,
  AdminSetCurrentProductVersionRequestSchema,
  AdminVerifyOrderRequestSchema,
  AdminVerifyOrderResponseSchema,
  type AdminCloseRedemptionBatchRequest,
  type AdminDisableUserRequest,
  type AdminDisabledUserCommandResponse,
  type AdminGrantEntitlementRequest,
  type AdminGrantedEntitlementCommandResponse,
  type AdminChangeProductionOriginRequest,
  type AdminCurrentProductVersionCommandResponse,
  type AdminCreateRedemptionBatchRequest,
  type AdminCreateRedemptionBatchResponse,
  type AdminGenerateRedemptionCodesRequest,
  type AdminGenerateRedemptionCodesResponse,
  type AdminPauseRedemptionBatchRequest,
  type AdminProcessDeletionRequest,
  type AdminProcessedDeletionCommandResponse,
  type AdminProductVersionCommandResponse,
  type AdminProductionOriginCommandResponse,
  type AdminPublishProductVersionRequest,
  type AdminRedemptionBatchCommandResponse,
  type AdminRetireProductVersionRequest,
  type AdminRestoreEntitlementRequest,
  type AdminRestoredEntitlementCommandResponse,
  type AdminRevokeEntitlementRequest,
  type AdminRevokedEntitlementCommandResponse,
  type AdminSetCurrentProductVersionRequest,
  type AdminVerifyOrderRequest,
  type AdminVerifyOrderResponse,
  type ContractSchema,
} from '@aisenhub/contracts';

import { withIdempotencyKey, type AdminClient, type AdminResponse } from './index';
import type { AdminResourceName } from './data-provider';

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type AdminCommandOptions = {
  readonly idempotencyKey?: string;
  readonly maxAttempts?: 1 | 2;
  readonly signal?: AbortSignal;
};

export type AdminCommandResult<T> = AdminResponse<T> & {
  readonly command: {
    readonly idempotencyKey: string;
    readonly entity: { readonly resource: AdminResourceName; readonly id: string };
    readonly invalidates: readonly AdminResourceName[];
  };
};

export interface AisenHubBusinessCommandClient {
  createRedemptionBatch(
    input: AdminCreateRedemptionBatchRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminCreateRedemptionBatchResponse>>;
  publishProductVersion(
    productVersionId: string,
    input: AdminPublishProductVersionRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminProductVersionCommandResponse>>;
  retireProductVersion(
    productVersionId: string,
    input: AdminRetireProductVersionRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminProductVersionCommandResponse>>;
  setCurrentProductVersion(
    productId: string,
    input: AdminSetCurrentProductVersionRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminCurrentProductVersionCommandResponse>>;
  changeProductionOrigin(
    originId: string,
    input: AdminChangeProductionOriginRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminProductionOriginCommandResponse>>;
  generateRedemptionCodes(
    batchId: string,
    input: AdminGenerateRedemptionCodesRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminGenerateRedemptionCodesResponse>>;
  pauseRedemptionBatch(
    batchId: string,
    input: AdminPauseRedemptionBatchRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminRedemptionBatchCommandResponse>>;
  closeRedemptionBatch(
    batchId: string,
    input: AdminCloseRedemptionBatchRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminRedemptionBatchCommandResponse>>;
  grantEntitlement(
    userId: string,
    input: AdminGrantEntitlementRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminGrantedEntitlementCommandResponse>>;
  revokeEntitlement(
    grantId: string,
    input: AdminRevokeEntitlementRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminRevokedEntitlementCommandResponse>>;
  restoreEntitlement(
    grantId: string,
    input: AdminRestoreEntitlementRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminRestoredEntitlementCommandResponse>>;
  disableUser(
    userId: string,
    input: AdminDisableUserRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminDisabledUserCommandResponse>>;
  processAccountDeletion(
    requestId: string,
    input: AdminProcessDeletionRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminProcessedDeletionCommandResponse>>;
  verifyOrder(
    orderId: string,
    input: AdminVerifyOrderRequest,
    options?: AdminCommandOptions,
  ): Promise<AdminCommandResult<AdminVerifyOrderResponse>>;
}

function encodeCommandId(id: string): string {
  if (!uuidPattern.test(id)) throw new Error('Admin command targets must be UUIDs.');
  return encodeURIComponent(id);
}

function createIdempotencyKey(input?: string): string {
  const key = input?.trim() || globalThis.crypto?.randomUUID();
  if (!key) throw new Error('An Idempotency-Key is required.');
  return key;
}

function isRetryableTransportError(error: unknown): boolean {
  if (error instanceof TypeError) return true;
  if (!error || typeof error !== 'object' || !('name' in error)) return false;
  return error.name === 'TimeoutError' || error.name === 'NetworkError';
}

async function runCommand<TInput, TOutput>(
  client: AdminClient,
  path: string,
  input: TInput,
  inputSchema: ContractSchema<TInput>,
  outputSchema: ContractSchema<TOutput>,
  entity:
    | { resource: AdminResourceName; id: string }
    | ((output: TOutput) => { resource: AdminResourceName; id: string }),
  invalidates: readonly AdminResourceName[],
  options: AdminCommandOptions | undefined,
): Promise<AdminCommandResult<TOutput>> {
  const validatedInput = inputSchema.parse(input);
  const idempotencyKey = createIdempotencyKey(options?.idempotencyKey);
  const init = withIdempotencyKey(
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(validatedInput),
      signal: options?.signal,
    },
    idempotencyKey,
  );
  const maxAttempts = options?.maxAttempts ?? 2;
  let attempt = 0;

  while (true) {
    try {
      const response = await client.request(path, outputSchema, init);
      const resolvedEntity = typeof entity === 'function' ? entity(response.data) : entity;
      return {
        ...response,
        command: { idempotencyKey, entity: resolvedEntity, invalidates },
      };
    } catch (error) {
      attempt += 1;
      if (attempt >= maxAttempts || !isRetryableTransportError(error)) throw error;
    }
  }
}

export function createBusinessCommandClient(client: AdminClient): AisenHubBusinessCommandClient {
  return {
    createRedemptionBatch(input, options) {
      return runCommand(
        client,
        '/v1/admin/redemption-batches',
        input,
        AdminCreateRedemptionBatchRequestSchema,
        AdminCreateRedemptionBatchResponseSchema,
        (output) => ({ resource: 'redemptionBatches', id: output.id }),
        ['redemptionBatches'],
        options,
      );
    },
    publishProductVersion(productVersionId, input, options) {
      const id = encodeCommandId(productVersionId);
      return runCommand(
        client,
        `/v1/admin/product-versions/${id}/publish`,
        input,
        AdminPublishProductVersionRequestSchema,
        AdminProductVersionCommandResponseSchema,
        { resource: 'productVersions', id: productVersionId },
        ['products', 'productVersions'],
        options,
      );
    },
    retireProductVersion(productVersionId, input, options) {
      const id = encodeCommandId(productVersionId);
      return runCommand(
        client,
        `/v1/admin/product-versions/${id}/retire`,
        input,
        AdminRetireProductVersionRequestSchema,
        AdminProductVersionCommandResponseSchema,
        { resource: 'productVersions', id: productVersionId },
        ['products', 'productVersions'],
        options,
      );
    },
    setCurrentProductVersion(productId, input, options) {
      const id = encodeCommandId(productId);
      return runCommand(
        client,
        `/v1/admin/products/${id}/set-current-version`,
        input,
        AdminSetCurrentProductVersionRequestSchema,
        AdminCurrentProductVersionCommandResponseSchema,
        { resource: 'products', id: productId },
        ['products', 'productVersions'],
        options,
      );
    },
    changeProductionOrigin(originId, input, options) {
      const id = encodeCommandId(originId);
      return runCommand(
        client,
        `/v1/admin/app-origins/${id}/change-production-origin`,
        input,
        AdminChangeProductionOriginRequestSchema,
        AdminProductionOriginCommandResponseSchema,
        { resource: 'origins', id: originId },
        ['applications', 'origins'],
        options,
      );
    },
    generateRedemptionCodes(batchId, input, options) {
      const id = encodeCommandId(batchId);
      return runCommand(
        client,
        `/v1/admin/redemption-batches/${id}/generate`,
        input,
        AdminGenerateRedemptionCodesRequestSchema,
        AdminGenerateRedemptionCodesResponseSchema,
        { resource: 'redemptionBatches', id: batchId },
        ['redemptionBatches', 'redemptionCodes'],
        options,
      );
    },
    pauseRedemptionBatch(batchId, input, options) {
      const id = encodeCommandId(batchId);
      return runCommand(
        client,
        `/v1/admin/redemption-batches/${id}/pause`,
        input,
        AdminPauseRedemptionBatchRequestSchema,
        AdminRedemptionBatchCommandResponseSchema,
        { resource: 'redemptionBatches', id: batchId },
        ['redemptionBatches'],
        options,
      );
    },
    closeRedemptionBatch(batchId, input, options) {
      const id = encodeCommandId(batchId);
      return runCommand(
        client,
        `/v1/admin/redemption-batches/${id}/close`,
        input,
        AdminCloseRedemptionBatchRequestSchema,
        AdminRedemptionBatchCommandResponseSchema,
        { resource: 'redemptionBatches', id: batchId },
        ['redemptionBatches'],
        options,
      );
    },
    grantEntitlement(userId, input, options) {
      const id = encodeCommandId(userId);
      return runCommand(
        client,
        `/v1/admin/users/${id}/entitlements/grant`,
        input,
        AdminGrantEntitlementRequestSchema,
        AdminGrantedEntitlementCommandResponseSchema,
        { resource: 'entitlements', id: userId },
        ['users', 'entitlements'],
        options,
      );
    },
    revokeEntitlement(grantId, input, options) {
      const id = encodeCommandId(grantId);
      return runCommand(
        client,
        `/v1/admin/entitlements/${id}/revoke`,
        input,
        AdminRevokeEntitlementRequestSchema,
        AdminRevokedEntitlementCommandResponseSchema,
        { resource: 'entitlements', id: grantId },
        ['users', 'entitlements'],
        options,
      );
    },
    restoreEntitlement(grantId, input, options) {
      const id = encodeCommandId(grantId);
      return runCommand(
        client,
        `/v1/admin/entitlements/${id}/restore`,
        input,
        AdminRestoreEntitlementRequestSchema,
        AdminRestoredEntitlementCommandResponseSchema,
        (output) => ({ resource: 'entitlements', id: output.restoredGrantId }),
        ['users', 'entitlements'],
        options,
      );
    },
    disableUser(userId, input, options) {
      const id = encodeCommandId(userId);
      return runCommand(
        client,
        `/v1/admin/users/${id}/disable`,
        input,
        AdminDisableUserRequestSchema,
        AdminDisabledUserCommandResponseSchema,
        { resource: 'users', id: userId },
        ['users', 'entitlements'],
        options,
      );
    },
    processAccountDeletion(requestId, input, options) {
      const id = encodeCommandId(requestId);
      return runCommand(
        client,
        `/v1/admin/account-deletion-requests/${id}/process`,
        input,
        AdminProcessDeletionRequestSchema,
        AdminProcessedDeletionCommandResponseSchema,
        { resource: 'accountDeletionRequests', id: requestId },
        ['accountDeletionRequests', 'users'],
        options,
      );
    },
    verifyOrder(orderId, input, options) {
      const id = encodeCommandId(orderId);
      return runCommand(
        client,
        `/v1/admin/orders/${id}/verify`,
        input,
        AdminVerifyOrderRequestSchema,
        AdminVerifyOrderResponseSchema,
        { resource: 'orders', id: orderId },
        ['orders', 'payments', 'entitlements', 'auditLogs'],
        options,
      );
    },
  };
}
