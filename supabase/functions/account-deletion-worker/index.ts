import { errorResponse, jsonResponse, requestId, serviceRpc } from '../_shared/platform-api.ts';

type DeletionClaim = {
  readonly deletion_request_id: string;
  readonly user_id: string;
  readonly status: 'processing';
  readonly attempt_count: number;
};

type DeletionResult = {
  readonly deletionRequestId: string;
  readonly userId: string;
  readonly status: 'completed';
  readonly completedAt: string;
  readonly revokedGrantCount: number;
  readonly deletedSessionCount: number;
  readonly anonymizedFeedbackCount: number;
  readonly detachedOrderCount: number;
  readonly disabledAdminCount: number;
  readonly idempotent: boolean;
};

type DeletionFailure = {
  readonly deletion_request_id: string;
  readonly status: 'failed';
  readonly attempt_count: number;
  readonly next_attempt_at: string;
  readonly last_error_code: string;
};

const workerAuthorizationHeader = 'authorization';

function serviceRoleKey(): string | undefined {
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
}

function isAuthorizedWorker(request: Request): boolean {
  const key = serviceRoleKey();
  return Boolean(key && request.headers.get(workerAuthorizationHeader) === `Bearer ${key}`);
}

function randomWorkerId(): string {
  return crypto.randomUUID();
}

function randomPassword(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}

async function anonymizeAuthUser(userId: string): Promise<void> {
  const baseUrl = Deno.env.get('SUPABASE_URL');
  const key = serviceRoleKey();
  if (!baseUrl || !key) throw new Error('Auth worker configuration is unavailable.');

  const response = await fetch(`${baseUrl}/auth/v1/admin/users/${userId}`, {
    method: 'PUT',
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      password: randomPassword(),
      user_metadata: { account_status: 'deleted' },
      ban_duration: '876000h',
    }),
  });

  if (!response.ok)
    throw new Error(response.status === 404 ? 'AUTH_USER_NOT_FOUND' : 'AUTH_USER_UPDATE_FAILED');
}

export async function handleDeletionWorker(request: Request): Promise<Response> {
  const id = requestId();
  if (request.method !== 'POST') {
    return errorResponse('METHOD_NOT_ALLOWED', 'Only POST is supported.', 405, id);
  }
  if (!isAuthorizedWorker(request)) {
    return errorResponse('WORKER_ACCESS_DENIED', 'Worker access is denied.', 403, id);
  }

  const claimWorkerId = randomWorkerId();
  try {
    const claims = await serviceRpc<DeletionClaim>('claim_account_deletion_request', {
      p_worker_id: claimWorkerId,
    });
    const claim = claims.length === 1 ? claims[0] : null;
    if (!claim) return jsonResponse({ processed: false, status: 'idle' }, 200, id);

    try {
      await anonymizeAuthUser(claim.user_id);
      const results = await serviceRpc<DeletionResult>('complete_account_deletion_request', {
        p_deletion_request_id: claim.deletion_request_id,
        p_worker_id: claimWorkerId,
        p_request_id: id,
      });
      const result = results.length === 1 ? results[0] : null;
      if (!result) throw new Error('The deletion completion result was invalid.');
      return jsonResponse({ processed: true, deletion: result }, 200, id);
    } catch (error) {
      const errorCode =
        error instanceof Error && error.message === 'AUTH_USER_NOT_FOUND'
          ? 'AUTH_USER_NOT_FOUND'
          : error instanceof Error && error.message === 'AUTH_USER_UPDATE_FAILED'
            ? 'AUTH_USER_UPDATE_FAILED'
            : 'DATABASE_STEP_FAILED';
      const failure = await serviceRpc<DeletionFailure>('fail_account_deletion_request', {
        p_request_id: claim.deletion_request_id,
        p_worker_id: claimWorkerId,
        p_error_code: errorCode,
      });
      const result = failure.length === 1 ? failure[0] : null;
      if (!result) {
        return errorResponse(
          'ACCOUNT_DELETION_UNAVAILABLE',
          'The account deletion worker is unavailable.',
          502,
          id,
        );
      }
      return jsonResponse({ processed: true, deletion: result }, 200, id);
    }
  } catch {
    return errorResponse(
      'ACCOUNT_DELETION_UNAVAILABLE',
      'The account deletion worker is unavailable.',
      502,
      id,
    );
  }
}

if (typeof Deno !== 'undefined' && typeof Deno.serve === 'function') {
  Deno.serve(handleDeletionWorker);
}
