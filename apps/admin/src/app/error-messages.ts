import type { AdminClientError } from '@aisenhub/admin-client';
import type { OpenNotificationParams } from '@refinedev/core';

export function getAdminErrorNotification(error: unknown): OpenNotificationParams {
  const clientError = error as Partial<AdminClientError> | null;
  const status = clientError?.status;
  const code = clientError?.code;

  if (status === 401) {
    return {
      type: 'error',
      message: 'Session expired',
      description: 'Sign in again to continue working in the Admin console.',
    };
  }
  if (status === 403) {
    return {
      type: 'error',
      message: 'Permission denied',
      description: 'Your Admin role does not allow this operation.',
    };
  }
  if (code === 'MFA_REQUIRED') {
    return {
      type: 'error',
      message: 'Authentication elevation required',
      description: 'Complete MFA before retrying this high-risk operation.',
    };
  }
  if (
    status === 409 ||
    code === 'RESOURCE_VERSION_CONFLICT' ||
    code === 'INVALID_STATE_TRANSITION'
  ) {
    return {
      type: 'error',
      message: 'State conflict',
      description: 'The record changed before this operation completed. Refresh and try again.',
    };
  }
  if (status === 422 || code === 'VALIDATION_ERROR') {
    return {
      type: 'error',
      message: 'Validation error',
      description: 'Review the highlighted values and submit again.',
    };
  }
  if (status === 429) {
    return {
      type: 'error',
      message: 'Too many requests',
      description: 'Wait briefly before trying this operation again.',
    };
  }
  return {
    type: 'error',
    message: 'Operation unavailable',
    description: 'The operation could not be completed. Contact support with the request ID.',
  };
}
