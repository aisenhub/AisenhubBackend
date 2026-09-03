export type VerifiedAccessToken = {
  readonly userId: string;
  readonly issuer: string;
  readonly audience: string;
  readonly expiresAt: number;
  readonly issuedAt: number | null;
  readonly clientId: string;
  readonly role: string;
  readonly aal: string | null;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type ApplicationContext = {
  readonly requestId: string;
  readonly userId: string;
  readonly profileStatus: 'active';
  readonly clientId: string;
  readonly applicationId: string;
  readonly applicationSlug: string;
  readonly membershipId: string;
  readonly membershipStatus: 'active';
  readonly aal: string | null;
};

export type ApplicationContextRow = {
  readonly user_id: string;
  readonly profile_status: string;
  readonly client_id: string;
  readonly client_status: string;
  readonly application_id: string;
  readonly application_slug: string;
  readonly application_status: string;
  readonly membership_id: string | null;
  readonly membership_status: string | null;
  readonly membership_policy: string;
};

export type ApplicationContextFailureCode =
  | 'AUTHENTICATION_REQUIRED'
  | 'ACCOUNT_DISABLED'
  | 'OAUTH_CLIENT_NOT_FOUND'
  | 'OAUTH_CLIENT_DISABLED'
  | 'APPLICATION_DISABLED'
  | 'MEMBERSHIP_REQUIRED'
  | 'MEMBERSHIP_SUSPENDED'
  | 'ORIGIN_NOT_ALLOWED'
  | 'INTERNAL_ERROR';

const failureStatuses: Record<ApplicationContextFailureCode, number> = {
  AUTHENTICATION_REQUIRED: 401,
  ACCOUNT_DISABLED: 403,
  OAUTH_CLIENT_NOT_FOUND: 403,
  OAUTH_CLIENT_DISABLED: 403,
  APPLICATION_DISABLED: 403,
  MEMBERSHIP_REQUIRED: 403,
  MEMBERSHIP_SUSPENDED: 403,
  ORIGIN_NOT_ALLOWED: 403,
  INTERNAL_ERROR: 502,
};

const failureMessages: Record<ApplicationContextFailureCode, string> = {
  AUTHENTICATION_REQUIRED: 'Authentication is required.',
  ACCOUNT_DISABLED: 'This account cannot access the application.',
  OAUTH_CLIENT_NOT_FOUND: 'The OAuth client is not registered.',
  OAUTH_CLIENT_DISABLED: 'The OAuth client is disabled.',
  APPLICATION_DISABLED: 'The application is not available.',
  MEMBERSHIP_REQUIRED: 'An active application membership is required.',
  MEMBERSHIP_SUSPENDED: 'The application membership is suspended.',
  ORIGIN_NOT_ALLOWED: 'The request Origin is not allowed for this application.',
  INTERNAL_ERROR: 'The application context could not be resolved.',
};

export class ApplicationContextError extends Error {
  readonly code: ApplicationContextFailureCode;
  readonly status: number;

  constructor(code: ApplicationContextFailureCode) {
    super(failureMessages[code]);
    this.name = 'ApplicationContextError';
    this.code = code;
    this.status = failureStatuses[code];
  }
}

export type ApplicationContextKernelOptions = {
  readonly verifyAccessToken?: (token: string) => Promise<VerifiedAccessToken>;
  readonly resolveContext: (userId: string, clientId: string) => Promise<unknown>;
  readonly resolveOrigin?: (origin: string) => Promise<string | null>;
};

export type ApplicationContextKernel = {
  authenticate(request: Request, requestId: string): Promise<ApplicationContext>;
};

function bearerToken(request: Request): string {
  const header = request.headers.get('authorization')?.trim() ?? '';
  const match = /^Bearer\s+([^\s]+)$/i.exec(header);
  if (!match) throw new ApplicationContextError('AUTHENTICATION_REQUIRED');
  return match[1];
}

function isContextRow(value: unknown): value is ApplicationContextRow {
  if (!value || typeof value !== 'object') return false;
  const row = value as Record<string, unknown>;
  return (
    typeof row.user_id === 'string' &&
    typeof row.profile_status === 'string' &&
    typeof row.client_id === 'string' &&
    typeof row.client_status === 'string' &&
    typeof row.application_id === 'string' &&
    typeof row.application_slug === 'string' &&
    typeof row.application_status === 'string' &&
    (typeof row.membership_id === 'string' || row.membership_id === null) &&
    (typeof row.membership_status === 'string' || row.membership_status === null) &&
    typeof row.membership_policy === 'string'
  );
}

function contextRow(value: unknown): ApplicationContextRow {
  const row = Array.isArray(value) ? (value.length === 1 ? value[0] : null) : value;
  if (!isContextRow(row)) throw new ApplicationContextError('INTERNAL_ERROR');
  return row;
}

function assertResolvedIdentity(row: ApplicationContextRow, token: VerifiedAccessToken): void {
  if (
    !uuidPattern.test(row.user_id) ||
    !uuidPattern.test(row.application_id) ||
    (row.membership_id !== null && !uuidPattern.test(row.membership_id)) ||
    row.user_id !== token.userId ||
    row.client_id !== token.clientId ||
    !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(row.application_slug)
  ) {
    throw new ApplicationContextError('INTERNAL_ERROR');
  }
}

function requireActiveContext(
  row: ApplicationContextRow,
): asserts row is ApplicationContextRow & { readonly membership_id: string } {
  if (row.profile_status !== 'active') {
    throw new ApplicationContextError('ACCOUNT_DISABLED');
  }
  if (row.client_status !== 'active') {
    throw new ApplicationContextError('OAUTH_CLIENT_DISABLED');
  }
  if (row.application_status !== 'active') {
    throw new ApplicationContextError('APPLICATION_DISABLED');
  }
  if (row.membership_id === null || row.membership_status === null) {
    throw new ApplicationContextError('MEMBERSHIP_REQUIRED');
  }
  if (row.membership_status === 'suspended') {
    throw new ApplicationContextError('MEMBERSHIP_SUSPENDED');
  }
  if (row.membership_status !== 'active') {
    throw new ApplicationContextError('MEMBERSHIP_REQUIRED');
  }
}

export function createApplicationContextKernel(
  options: ApplicationContextKernelOptions,
): ApplicationContextKernel {
  const verifyAccessToken = options.verifyAccessToken;
  if (!verifyAccessToken) throw new Error('An access-token verifier is required.');

  return {
    async authenticate(request, requestId) {
      const token = bearerToken(request);
      let verified: VerifiedAccessToken;
      try {
        verified = await verifyAccessToken(token);
      } catch {
        throw new ApplicationContextError('AUTHENTICATION_REQUIRED');
      }

      let resolved: unknown;
      try {
        resolved = await options.resolveContext(verified.userId, verified.clientId);
      } catch {
        throw new ApplicationContextError('INTERNAL_ERROR');
      }
      const row = contextRow(resolved);
      assertResolvedIdentity(row, verified);
      requireActiveContext(row);

      const origin = request.headers.get('origin');
      if (origin !== null) {
        if (!options.resolveOrigin) throw new ApplicationContextError('INTERNAL_ERROR');
        let originApplication: string | null;
        try {
          originApplication = await options.resolveOrigin(origin);
        } catch {
          throw new ApplicationContextError('INTERNAL_ERROR');
        }
        if (originApplication !== row.application_slug) {
          throw new ApplicationContextError('ORIGIN_NOT_ALLOWED');
        }
      }

      return {
        requestId,
        userId: row.user_id,
        profileStatus: 'active',
        clientId: row.client_id,
        applicationId: row.application_id,
        applicationSlug: row.application_slug,
        membershipId: row.membership_id,
        membershipStatus: 'active',
        aal: verified.aal,
      };
    },
  };
}

export function applicationContextErrorResponse(
  error: unknown,
  requestId: string,
): Response | null {
  if (!(error instanceof ApplicationContextError)) return null;
  return new Response(
    JSON.stringify({
      error: {
        code: error.code,
        message: error.message,
        requestId,
      },
    }),
    {
      status: error.status,
      headers: {
        'content-type': 'application/json',
        'x-request-id': requestId,
      },
    },
  );
}
