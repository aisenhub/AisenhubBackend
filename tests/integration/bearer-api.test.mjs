import { afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';

const apiOrigin = 'http://api.local';
const accountOrigin = 'http://localhost:5173';
const adminOrigin = 'http://localhost:5174';
const userId = '00000000-0000-4000-8000-000000000001';
const accountAppId = '20000000-0000-4000-8000-000000000002';
const adminAppId = '20000000-0000-4000-8000-000000000003';
const originalFetch = globalThis.fetch;

let keyPair;
let publicJwk;
let lastServiceCall;

function encode(value) {
  return btoa(JSON.stringify(value)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function response(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

async function tokenFor(clientId, aal = 'aal1') {
  const header = encode({ alg: 'RS256', kid: 'integration-key', typ: 'JWT' });
  const now = Math.floor(Date.now() / 1000);
  const payload = encode({
    iss: `${apiOrigin}/auth/v1`,
    sub: userId,
    aud: 'authenticated',
    exp: now + 3600,
    iat: now,
    client_id: clientId,
    role: 'authenticated',
    aal,
  });
  const signature = await crypto.subtle.sign(
    { name: 'RSASSA-PKCS1-v1_5' },
    keyPair.privateKey,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '')}`;
}

function contextFor(clientId) {
  const isAdmin = clientId === 'admin-local-web';
  return [
    {
      user_id: userId,
      profile_status: 'active',
      client_id: clientId,
      client_status: 'active',
      application_id: isAdmin ? adminAppId : accountAppId,
      application_slug: isAdmin ? 'admin' : 'account',
      application_status: 'active',
      membership_id: `00000000-0000-4000-8000-${isAdmin ? '000000000003' : '000000000002'}`,
      membership_status: 'active',
      membership_policy: 'explicit',
    },
  ];
}

async function mockedFetch(url, init) {
  const parsedUrl = new URL(url);
  const pathname = parsedUrl.pathname;
  const body = JSON.parse(init?.body ?? '{}');
  if (url === `${apiOrigin}/auth/v1/.well-known/jwks.json`) {
    return response({ keys: [publicJwk] });
  }
  if (pathname.endsWith('/resolve_app_origin')) {
    const appSlug =
      body.p_origin === accountOrigin ? 'account' : body.p_origin === adminOrigin ? 'admin' : null;
    return response(appSlug ? [{ app_slug: appSlug, environment: 'development' }] : []);
  }
  if (pathname.endsWith('/resolve_application_context')) {
    return response(contextFor(body.p_client_id));
  }
  if (pathname.endsWith('/resolve_admin_membership')) {
    return response([
      { user_id: userId, display_name: 'Local Admin', role: 'admin', status: 'active' },
    ]);
  }
  if (pathname.endsWith('/current_profile')) {
    return response([
      { userId, displayName: 'Account User', avatarUrl: null, locale: 'en-US', status: 'active' },
    ]);
  }
  if (pathname.endsWith('/list_user_application_memberships')) return response([]);
  if (pathname.endsWith('/list_user_application_entitlements')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        feature: 'lens.export',
        value: { max: 10 },
        source_product: 'AISENLENS_PRO',
        expires_at: null,
      },
    ]);
  }
  if (pathname.endsWith('/check_access')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        allowed: true,
        feature: body.p_feature_code,
        value: { max: 10 },
        source_product: 'AISENLENS_PRO',
        expires_at: null,
        decision_id: '00000000-0000-4000-8000-000000000020',
      },
    ]);
  }
  if (pathname.endsWith('/check_application_access')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        allowed: true,
        feature: body.p_feature_code,
        value: { max: 10 },
        source_product: 'AISENLENS_PRO',
        expires_at: null,
        decision_id: '00000000-0000-4000-8000-000000000020',
      },
    ]);
  }
  if (pathname.endsWith('/redeem_application_code')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        redemption_id: '00000000-0000-4000-8000-000000000040',
        grant_id: '00000000-0000-4000-8000-000000000041',
        status: 'redeemed',
      },
    ]);
  }
  if (pathname.endsWith('/create_application_feedback')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        id: '00000000-0000-4000-8000-000000000042',
        status: 'open',
        created_at: '2026-09-03T00:00:00.000Z',
      },
    ]);
  }
  if (pathname.endsWith('/application_membership_command')) {
    lastServiceCall = { pathname, body };
    return response({
      id: body.p_membership_id,
      applicationId: accountAppId,
      userId,
      status: 'left',
      createdSource: 'oauth',
      joinedAt: '2026-09-01T00:00:00.000Z',
      activatedAt: '2026-09-01T00:00:00.000Z',
      suspendedAt: null,
      leftAt: '2026-09-03T00:00:00.000Z',
      deletedAt: null,
      auditLogId: '00000000-0000-4000-8000-000000000099',
    });
  }
  if (pathname.endsWith('/admin_list_application_memberships')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        id: '00000000-0000-4000-8000-000000000201',
        application_id: accountAppId,
        application_slug: 'account',
        application_name: 'Account',
        user_id: userId,
        membership_status: 'active',
        created_source: 'oauth',
        joined_at: '2026-09-01T00:00:00.000Z',
        activated_at: '2026-09-01T00:00:00.000Z',
        suspended_at: null,
        suspended_reason: null,
        left_at: null,
        deleted_at: null,
      },
    ]);
  }
  if (pathname.endsWith('/admin_list_application_oauth_clients')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        id: '00000000-0000-4000-8000-000000000202',
        application_id: accountAppId,
        provider: 'supabase',
        external_client_id: 'account-local-web',
        client_type: 'public',
        environment: 'development',
        name: 'Account Local Web',
        status: 'active',
        created_at: '2026-09-01T00:00:00.000Z',
        updated_at: '2026-09-01T00:00:00.000Z',
      },
    ]);
  }
  if (pathname.endsWith('/admin_application_membership_command')) {
    lastServiceCall = { pathname, body };
    return response({
      id: '00000000-0000-4000-8000-000000000201',
      applicationId: accountAppId,
      userId,
      status: body.p_action === 'suspend' ? 'suspended' : 'pending',
      createdSource: 'admin',
      joinedAt: '2026-09-01T00:00:00.000Z',
      activatedAt: null,
      suspendedAt: body.p_action === 'suspend' ? '2026-09-03T00:00:00.000Z' : null,
      leftAt: null,
      deletedAt: null,
      auditLogId: '00000000-0000-4000-8000-000000000203',
    });
  }
  if (pathname.endsWith('/admin_oauth_client_command')) {
    lastServiceCall = { pathname, body };
    return response({
      id: '00000000-0000-4000-8000-000000000202',
      applicationId: accountAppId,
      provider: body.p_provider ?? 'supabase',
      externalClientId: body.p_external_client_id ?? 'account-local-web',
      clientType: body.p_client_type ?? 'public',
      environment: body.p_environment ?? 'development',
      name: body.p_name ?? 'Account Local Web',
      status: body.p_action === 'disable' ? 'disabled' : 'active',
      createdAt: '2026-09-01T00:00:00.000Z',
      updatedAt: '2026-09-03T00:00:00.000Z',
      auditLogId: '00000000-0000-4000-8000-000000000204',
    });
  }
  if (pathname.endsWith('/admin_query_resource')) {
    lastServiceCall = { pathname, body };
    return response([
      {
        items: [{ id: '00000000-0000-4000-8000-000000000030', slug: 'admin', status: 'active' }],
        page: { hasMore: false, nextCursor: null },
      },
    ]);
  }
  return response([]);
}

beforeAll(async () => {
  globalThis.Deno = {
    env: {
      get: (name) =>
        ({
          SUPABASE_URL: apiOrigin,
          SUPABASE_ANON_KEY: 'anon-key',
          SUPABASE_SERVICE_ROLE_KEY: 'service-role-key',
          REDEMPTION_PEPPER: 'integration-redemption-pepper',
          REDEMPTION_PEPPER_VERSION: '1',
        })[name],
    },
  };
  keyPair = await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  );
  publicJwk = Object.assign(await crypto.subtle.exportKey('jwk', keyPair.publicKey), {
    kid: 'integration-key',
    alg: 'RS256',
    use: 'sig',
  });
});

beforeEach(() => {
  globalThis.fetch = mockedFetch;
  lastServiceCall = null;
});

describe('Bearer application API', () => {
  it('resolves application context and profile from the verified client identity', async () => {
    const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
    const token = await tokenFor('account-local-web');
    const responseValue = await routePlatformApi(
      new Request(`${apiOrigin}/v1/app/context`, {
        headers: { Authorization: `Bearer ${token}`, Origin: accountOrigin },
      }),
    );
    expect(responseValue.status).toBe(200);
    expect((await responseValue.json()).data.application.slug).toBe('account');
    expect(responseValue.headers.get('access-control-allow-origin')).toBe(accountOrigin);
  });

  it('allows no-Origin service requests but rejects a mismatched registered Origin', async () => {
    const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
    const token = await tokenFor('account-local-web');
    const withoutOrigin = await routePlatformApi(
      new Request(`${apiOrigin}/v1/app/context`, {
        headers: { Authorization: `Bearer ${token}` },
      }),
    );
    expect(withoutOrigin.status).toBe(200);
    const mismatched = await routePlatformApi(
      new Request(`${apiOrigin}/v1/app/context`, {
        headers: { Authorization: `Bearer ${token}`, Origin: adminOrigin },
      }),
    );
    expect(mismatched.status).toBe(403);
    expect((await mismatched.json()).error.code).toBe('ORIGIN_NOT_ALLOWED');
  });

  it('uses the verified application for access decisions and rejects unknown routes', async () => {
    const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
    const token = await tokenFor('account-local-web');
    const access = await routePlatformApi(
      new Request(`${apiOrigin}/v1/app/access/lens.export`, {
        headers: { Authorization: `Bearer ${token}` },
      }),
    );
    expect(access.status).toBe(200);
    expect(lastServiceCall.body.p_application_id).toBe(accountAppId);
    const unknownRoute = await routePlatformApi(new Request(`${apiOrigin}/v1/unknown-route`));
    expect(unknownRoute.status).toBe(404);
  });

  it('scopes entitlement projections to the resolved application id', async () => {
    const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
    const token = await tokenFor('account-local-web');
    const entitlementResponse = await routePlatformApi(
      new Request(`${apiOrigin}/v1/app/entitlements`, {
        headers: { Authorization: `Bearer ${token}` },
      }),
    );
    expect(entitlementResponse.status).toBe(200);
    expect(lastServiceCall.pathname).toContain('list_user_application_entitlements');
    expect(lastServiceCall.body.p_application_id).toBe(accountAppId);
  });

  it('passes the resolved application into redemption without accepting an app from the body', async () => {
    const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
    const token = await tokenFor('account-local-web');
    const redemptionResponse = await routePlatformApi(
      new Request(`${apiOrigin}/v1/app/redemptions`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': 'redemption-application-001',
        },
        body: JSON.stringify({ code: 'AH-LOCAL-ABCD-2345', applicationId: adminAppId }),
      }),
    );
    expect(redemptionResponse.status).toBe(200);
    expect(lastServiceCall.pathname).toContain('redeem_application_code');
    expect(lastServiceCall.body.p_application_id).toBe(accountAppId);
    expect(lastServiceCall.body).not.toHaveProperty('p_app_slug');
  });

  it('attributes feedback to the resolved application membership', async () => {
    const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
    const token = await tokenFor('account-local-web');
    const feedbackResponse = await routePlatformApi(
      new Request(`${apiOrigin}/v1/app/feedback`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          kind: 'bug',
          title: 'Scoped feedback',
          content: 'Scoped feedback content',
        }),
      }),
    );
    expect(feedbackResponse.status).toBe(201);
    expect(lastServiceCall.pathname).toContain('create_application_feedback');
    expect(lastServiceCall.body.p_application_id).toBe(accountAppId);
    expect(lastServiceCall.body.p_membership_id).toBe('00000000-0000-4000-8000-000000000002');
    expect(lastServiceCall.body).not.toHaveProperty('p_app_slug');
  });

  it('leaves only the current application membership through a named command', async () => {
    const { routePlatformApi } = await import('../../supabase/functions/_shared/platform-api.ts');
    const token = await tokenFor('account-local-web');
    const responseValue = await routePlatformApi(
      new Request(
        `${apiOrigin}/v1/account/applications/00000000-0000-4000-8000-000000000002/leave`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
            'Idempotency-Key': 'leave-application-001',
          },
          body: JSON.stringify({ reason: 'No longer using this application' }),
        },
      ),
    );
    expect(responseValue.status).toBe(200);
    expect(lastServiceCall.body.p_action).toBe('leave');
    expect(lastServiceCall.body.p_actor_id).toBe(userId);
  });
});

describe('Bearer Admin API', () => {
  it('reads Admin identity and queries with an OAuth bearer token', async () => {
    const { routePlatformAdmin } = await import('../../supabase/functions/_shared/admin-api.ts');
    const token = await tokenFor('admin-local-web', 'aal2');
    const session = await routePlatformAdmin(
      new Request(`${apiOrigin}/v1/admin/session`, {
        headers: { Authorization: `Bearer ${token}`, Origin: adminOrigin },
      }),
    );
    expect(session.status).toBe(200);
    expect((await session.json()).data).toMatchObject({
      role: 'admin',
      aal: 'aal2',
      mfaState: 'verified',
    });
    const query = await routePlatformAdmin(
      new Request(`${apiOrigin}/v1/admin/applications?limit=10`, {
        headers: { Authorization: `Bearer ${token}` },
      }),
    );
    expect(query.status).toBe(200);
    expect(lastServiceCall.body.p_actor_id).toBe(userId);
    const scopedAuditQuery = await routePlatformAdmin(
      new Request(`${apiOrigin}/v1/admin/audit-logs?applicationId=${accountAppId}`, {
        headers: { Authorization: `Bearer ${token}` },
      }),
    );
    expect(scopedAuditQuery.status).toBe(200);
    expect(lastServiceCall.body.p_application_id).toBe(accountAppId);
  });

  it('lists application operations and sends named audited commands through the Admin client boundary', async () => {
    const { routePlatformAdmin } = await import('../../supabase/functions/_shared/admin-api.ts');
    const token = await tokenFor('admin-local-web', 'aal2');
    const commonHeaders = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
    const memberships = await routePlatformAdmin(
      new Request(`${apiOrigin}/v1/admin/applications/${accountAppId}/memberships`, {
        headers: commonHeaders,
      }),
    );
    expect(memberships.status).toBe(200);
    expect((await memberships.json()).data.items[0]).not.toHaveProperty('secret');
    expect(lastServiceCall.body.p_application_id).toBe(accountAppId);

    const suspend = await routePlatformAdmin(
      new Request(
        `${apiOrigin}/v1/admin/applications/${accountAppId}/memberships/00000000-0000-4000-8000-000000000201/suspend`,
        {
          method: 'POST',
          headers: { ...commonHeaders, 'Idempotency-Key': 'admin-membership-suspend-001' },
          body: JSON.stringify({ reason: 'Security review', confirmation: true }),
        },
      ),
    );
    expect(suspend.status).toBe(200);
    expect(lastServiceCall.body.p_action).toBe('suspend');

    const clients = await routePlatformAdmin(
      new Request(`${apiOrigin}/v1/admin/applications/${accountAppId}/oauth-clients`, {
        headers: commonHeaders,
      }),
    );
    expect(clients.status).toBe(200);
    expect((await clients.json()).data.items[0]).toMatchObject({
      provider: 'supabase',
      externalClientId: 'account-local-web',
    });

    const createClient = await routePlatformAdmin(
      new Request(`${apiOrigin}/v1/admin/applications/${accountAppId}/oauth-clients`, {
        method: 'POST',
        headers: { ...commonHeaders, 'Idempotency-Key': 'admin-oauth-create-001' },
        body: JSON.stringify({
          provider: 'supabase',
          externalClientId: 'account-new-web',
          clientType: 'public',
          environment: 'development',
          name: 'Account New Web',
          reason: 'Register web client',
          confirmation: true,
        }),
      }),
    );
    expect(createClient.status).toBe(201);
    expect(lastServiceCall.body.p_action).toBe('create');
    expect(lastServiceCall.body).not.toHaveProperty('p_secret');
  });

  it('requires a bearer token and rejects the removed session route', async () => {
    const { routePlatformAdmin } = await import('../../supabase/functions/_shared/admin-api.ts');
    const missing = await routePlatformAdmin(new Request(`${apiOrigin}/v1/admin/applications`));
    expect(missing.status).toBe(401);
    const legacy = await routePlatformAdmin(
      new Request(`${apiOrigin}/v1/admin/session`, {
        headers: { Cookie: '__Host-aisenhub_session=legacy-token' },
      }),
    );
    expect(legacy.status).toBe(401);
  });
});

afterEach(() => {
  globalThis.fetch = originalFetch;
});
