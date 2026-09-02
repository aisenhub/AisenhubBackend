import {
  errorResponse,
  jsonResponse,
  requestIdFromRequest,
  serviceRpc,
} from '../_shared/platform-api.ts';
import { withTelemetry } from '../_shared/telemetry.ts';

type CleanupResult = {
  readonly dryRun: boolean;
  readonly sessionCount: number;
  readonly redemptionIpHashCount: number;
  readonly auditIpHashCount: number;
  readonly idempotencyResponseCount: number;
  readonly idempotencyDeletedCount: number;
  readonly batchSize: number;
};

type CleanupConfig = {
  readonly sessionGraceSeconds: number;
  readonly securityContextRetentionSeconds: number;
  readonly idempotencyResponseRetentionSeconds: number;
  readonly batchSize: number;
  readonly dryRun: boolean;
};

const runtimeEnvironment = 'PLATFORM_RUNTIME_ENVIRONMENT';
const sessionGrace = 'PLATFORM_CLEANUP_SESSION_GRACE_SECONDS';
const securityRetention = 'PLATFORM_CLEANUP_SECURITY_CONTEXT_RETENTION_SECONDS';
const idempotencyRetention = 'PLATFORM_CLEANUP_IDEMPOTENCY_RESPONSE_RETENTION_SECONDS';
const batchSize = 'PLATFORM_CLEANUP_BATCH_SIZE';
const dryRun = 'PLATFORM_CLEANUP_DRY_RUN';

function serviceRoleKey(): string | undefined {
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
}

function isAuthorizedWorker(request: Request): boolean {
  const key = serviceRoleKey();
  return Boolean(key && request.headers.get('authorization') === `Bearer ${key}`);
}

function environment(): string {
  return Deno.env.get(runtimeEnvironment)?.trim().toLowerCase() || 'local';
}

function numericConfig(name: string, fallback: number, required: boolean): number {
  const raw = Deno.env.get(name)?.trim();
  if (!raw) {
    if (required) throw new Error('CLEANUP_CONFIG_INVALID');
    return fallback;
  }
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < 0) throw new Error('CLEANUP_CONFIG_INVALID');
  return value;
}

function booleanConfig(name: string, fallback: boolean, required: boolean): boolean {
  const raw = Deno.env.get(name)?.trim().toLowerCase();
  if (!raw) {
    if (required) throw new Error('CLEANUP_CONFIG_INVALID');
    return fallback;
  }
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  throw new Error('CLEANUP_CONFIG_INVALID');
}

function cleanupConfig(): CleanupConfig {
  const currentEnvironment = environment();
  if (!['local', 'staging', 'production'].includes(currentEnvironment)) {
    throw new Error('CLEANUP_CONFIG_INVALID');
  }
  const required = currentEnvironment !== 'local';
  const configuredBatchSize = numericConfig(batchSize, 100, required);
  if (configuredBatchSize < 1 || configuredBatchSize > 1000) {
    throw new Error('CLEANUP_CONFIG_INVALID');
  }
  return {
    sessionGraceSeconds: numericConfig(sessionGrace, 86_400, required),
    securityContextRetentionSeconds: numericConfig(securityRetention, 2_592_000, required),
    idempotencyResponseRetentionSeconds: numericConfig(idempotencyRetention, 0, required),
    batchSize: configuredBatchSize,
    dryRun: booleanConfig(dryRun, false, required),
  };
}

function cutoff(seconds: number, now: number): string {
  return new Date(now - seconds * 1000).toISOString();
}

export async function handleRetentionCleanup(request: Request): Promise<Response> {
  const id = requestIdFromRequest(request);
  if (request.method !== 'POST') {
    return errorResponse('METHOD_NOT_ALLOWED', 'Only POST is supported.', 405, id);
  }
  if (!isAuthorizedWorker(request)) {
    return errorResponse('WORKER_ACCESS_DENIED', 'Worker access is denied.', 403, id);
  }

  try {
    const config = cleanupConfig();
    const now = Date.now();
    const rows = await serviceRpc<CleanupResult>('run_retention_cleanup', {
      p_session_expired_before: cutoff(config.sessionGraceSeconds, now),
      p_security_context_before: cutoff(config.securityContextRetentionSeconds, now),
      p_idempotency_response_before: cutoff(config.idempotencyResponseRetentionSeconds, now),
      p_batch_size: config.batchSize,
      p_dry_run: config.dryRun,
    });
    const result = rows.length === 1 ? rows[0] : null;
    if (!result) throw new Error('CLEANUP_RESULT_INVALID');
    return jsonResponse({ cleanup: result }, 200, id);
  } catch (error) {
    if (error instanceof Error && error.message === 'CLEANUP_CONFIG_INVALID') {
      return errorResponse('CLEANUP_CONFIG_INVALID', 'Cleanup configuration is invalid.', 500, id);
    }
    return errorResponse('CLEANUP_UNAVAILABLE', 'The cleanup worker is unavailable.', 502, id);
  }
}

if (typeof Deno !== 'undefined' && typeof Deno.serve === 'function') {
  Deno.serve((request) => withTelemetry(request, handleRetentionCleanup));
}
