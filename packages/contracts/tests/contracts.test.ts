import { describe, expect, it } from 'vitest';

import {
  AdminRoles,
  AdminSessionResponseSchema,
  ApiErrorEnvelopeSchema,
  ApiSuccessEnvelopeSchema,
  ErrorCodes,
  MeResponseSchema,
  PaginationQuerySchema,
  PermissionActions,
  PermissionActionSchema,
  SessionExchangeRequestSchema,
  SessionExchangeResponseSchema,
  SessionResponseSchema,
  parseApiError,
} from '../src/index';

const requestId = '00000000-0000-4000-8000-000000000001';

describe('platform contract primitives', () => {
  it('requires requestId and validates the stable error envelope', () => {
    const parsed = ApiErrorEnvelopeSchema.parse({
      error: {
        code: ErrorCodes.REASON_REQUIRED,
        message: 'A reason is required.',
        requestId,
      },
    });

    expect(parsed.error.requestId).toBe(requestId);
    expect(() => parseApiError({ error: { code: ErrorCodes.REASON_REQUIRED } })).toThrow();
  });

  it('rejects invalid pagination and unknown permission actions', () => {
    expect(PaginationQuerySchema.parse({ limit: '10' }).limit).toBe(10);
    expect(() => PaginationQuerySchema.parse({ limit: 0 })).toThrow();
    expect(() => PermissionActionSchema.parse('orders.write')).toThrow();
  });

  it('keeps error codes, permission actions, and roles unique', () => {
    expect(new Set(Object.values(ErrorCodes)).size).toBe(Object.values(ErrorCodes).length);
    expect(new Set(PermissionActions).size).toBe(PermissionActions.length);
    expect(new Set(AdminRoles).size).toBe(AdminRoles.length);
  });

  it('preserves the success envelope serialization shape', () => {
    const schema = ApiSuccessEnvelopeSchema(PermissionActionSchema);
    const payload = schema.parse({ data: 'audit_logs.read', requestId });
    expect(JSON.stringify(payload)).toBe(
      '{"data":"audit_logs.read","requestId":"00000000-0000-4000-8000-000000000001"}',
    );
  });

  it('covers the session exchange, session status, and me response shapes', () => {
    expect(SessionExchangeRequestSchema.parse({})).toEqual({});
    expect(() => SessionExchangeRequestSchema.parse({ accessToken: 'raw-token' })).toThrow();

    const exchange = SessionExchangeResponseSchema.parse({
      authenticated: true,
      identity: {
        userId: requestId,
        displayName: 'Owner',
        avatarUrl: null,
        locale: 'zh-CN',
        status: 'active',
      },
      expiresAt: '2026-09-02T00:00:00.000Z',
      csrfToken: 'csrf-token-is-in-memory-only',
    });

    expect(exchange.identity.userId).toBe(requestId);
    expect(SessionResponseSchema.parse(exchange).authenticated).toBe(true);
    expect(
      SessionResponseSchema.parse({
        authenticated: false,
        identity: null,
        expiresAt: null,
      }).authenticated,
    ).toBe(false);

    expect(() =>
      MeResponseSchema.parse({ profile: { ...exchange.identity, deletedAt: null } }),
    ).toThrow();
  });

  it('keeps Admin session identity minimal and excludes permissions or secrets', () => {
    const adminSession = AdminSessionResponseSchema.parse({
      authenticated: true,
      identity: { userId: requestId, displayName: 'Owner' },
      role: 'owner',
      aal: 'aal2',
      mfaState: 'verified',
      expiresAt: '2026-09-02T00:00:00.000Z',
    });

    expect(adminSession.role).toBe('owner');
    expect(() => AdminSessionResponseSchema.parse({ ...adminSession, permissions: [] })).toThrow();
    expect(() =>
      AdminSessionResponseSchema.parse({ ...adminSession, tokenHash: 'digest' }),
    ).toThrow();
  });
});
