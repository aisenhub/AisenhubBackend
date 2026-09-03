import { useEffect, useMemo, useState, type FormEvent } from 'react';

import { createPlatformClient, PlatformClientError } from '@aisenhub/platform-client';
import type {
  EntitlementsResponse,
  MeResponse,
  MyApplicationsResponse,
  PublicProductsResponse,
} from '@aisenhub/contracts';

import { AccountAuthClient, AccountAuthError } from './auth';
import './styles.css';

type ViewState = 'loading' | 'signed_out' | 'signing_in' | 'authenticated' | 'error';
type AuthenticatedSession = MeResponse;

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL ?? 'http://127.0.0.1:54321';
const platformApiUrl =
  import.meta.env.VITE_PLATFORM_API_URL ?? 'http://127.0.0.1:54321/functions/v1/platform-api';
const platformPublicApiUrl =
  import.meta.env.VITE_PLATFORM_PUBLIC_API_URL ??
  'http://127.0.0.1:54321/functions/v1/platform-public';

function readableError(error: unknown): string {
  if (error instanceof AccountAuthError) return error.message;
  if (error instanceof PlatformClientError) {
    if (error.code === 'AUTHENTICATION_REQUIRED')
      return 'Your session has expired. Please sign in again.';
    if (error.code === 'REDEMPTION_UNAVAILABLE')
      return 'This redemption code is invalid or no longer available.';
    return 'Something went wrong. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}

function createIdempotencyKey() {
  return globalThis.crypto.randomUUID();
}

export function App() {
  const [viewState, setViewState] = useState<ViewState>('loading');
  const [message, setMessage] = useState<string | null>(null);
  const [session, setSession] = useState<AuthenticatedSession | null>(null);
  const [products, setProducts] = useState<PublicProductsResponse['products']>([]);
  const [entitlements, setEntitlements] = useState<EntitlementsResponse['entitlements']>([]);
  const [applications, setApplications] = useState<MyApplicationsResponse['applications']>([]);
  const [redemptionCode, setRedemptionCode] = useState('');
  const [isRedeeming, setIsRedeeming] = useState(false);
  const [deletionConfirmed, setDeletionConfirmed] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const auth = useMemo(
    () =>
      new AccountAuthClient({
        supabaseUrl,
        clientId: import.meta.env.VITE_ACCOUNT_OAUTH_CLIENT_ID ?? 'account-local-web',
        redirectUri: `${window.location.origin}/`,
      }),
    [],
  );
  const client = useMemo(
    () =>
      createPlatformClient({
        baseUrl: platformApiUrl,
        publicBaseUrl: platformPublicApiUrl,
        accessToken: () => auth.accessToken,
      }),
    [auth],
  );

  async function loadAccountData() {
    const [catalog, currentEntitlements, currentApplications] = await Promise.all([
      client.getPublicProducts(),
      client.getEntitlements(),
      client.getApplications(),
    ]);
    setProducts(catalog.data.products);
    setEntitlements(currentEntitlements.data.entitlements);
    setApplications(currentApplications.data.applications);
  }

  useEffect(() => {
    let active = true;
    const callbackUrl = new URL(window.location.href);
    const hasAuthorizationCallback =
      callbackUrl.searchParams.has('code') && callbackUrl.searchParams.has('state');
    const authorization = hasAuthorizationCallback
      ? auth.completeAuthorization(callbackUrl).then(() => {
          window.history.replaceState(
            {},
            document.title,
            callbackUrl.origin + callbackUrl.pathname,
          );
        })
      : Promise.resolve();
    authorization
      .then(() => (auth.accessToken ? client.getProfile() : null))
      .then(async (response) => {
        if (!active) return;
        if (!response) {
          setViewState('signed_out');
          return;
        }
        setSession(response.data);
        await loadAccountData();
        if (active) setViewState('authenticated');
      })
      .catch((error: unknown) => {
        if (!active) return;
        setMessage(readableError(error));
        setViewState('error');
      });
    return () => {
      active = false;
    };
  }, [client]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage(null);
    setViewState('signing_in');
    try {
      const authorization = await auth.startAuthorization();
      window.location.assign(authorization.authorizationUrl);
    } catch (error: unknown) {
      setMessage(readableError(error));
      setViewState('signed_out');
    }
  }

  async function handleRedeem(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!redemptionCode.trim()) return;
    setMessage(null);
    setIsRedeeming(true);
    try {
      await client.redeem(redemptionCode.trim(), createIdempotencyKey());
      setRedemptionCode('');
      await loadAccountData();
      setMessage('Redemption completed. Your platform access is now updated.');
    } catch (error: unknown) {
      setMessage(readableError(error));
    } finally {
      setIsRedeeming(false);
    }
  }

  async function handleLeaveApplication(membershipId: string) {
    setMessage(null);
    try {
      await client.leaveApplication(
        membershipId,
        'User left the application from Account Center',
        createIdempotencyKey(),
      );
      setApplications((current) => current.filter((item) => item.id !== membershipId));
      setMessage('You left the application. Your global AisenHub identity remains active.');
    } catch (error: unknown) {
      setMessage(readableError(error));
    }
  }

  async function handleDeletion(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!deletionConfirmed) return;
    setMessage(null);
    setIsDeleting(true);
    try {
      await client.requestAccountDeletion(createIdempotencyKey());
      auth.signOut();
      setSession(null);
      setViewState('signed_out');
      setMessage('Your account deletion request was submitted.');
    } catch (error: unknown) {
      setMessage(readableError(error));
    } finally {
      setIsDeleting(false);
    }
  }

  async function handleLogout() {
    setMessage(null);
    try {
      await auth.signOut();
    } catch (error: unknown) {
      setMessage(readableError(error));
      return;
    }
    setSession(null);
    setProducts([]);
    setEntitlements([]);
    setApplications([]);
    setViewState('signed_out');
  }

  if (viewState === 'loading') {
    return (
      <main className="account-shell" aria-busy="true">
        <p className="status-text">Checking your session…</p>
      </main>
    );
  }

  if (viewState === 'error') {
    return (
      <main className="account-shell">
        <p className="error-text" role="alert">
          {message}
        </p>
      </main>
    );
  }

  if (viewState === 'authenticated' && session) {
    return (
      <main className="account-shell account-shell-top">
        <section className="account-card account-card-wide" aria-labelledby="welcome-title">
          <p className="eyebrow">AisenHub Account</p>
          <h1 id="welcome-title">
            Welcome back{session.profile.displayName ? `, ${session.profile.displayName}` : ''}.
          </h1>
          <p className="supporting-text">
            Your application access is active. Products and access are resolved by AisenHub.
          </p>
          {message && (
            <p className="notice-text" role="status">
              {message}
            </p>
          )}

          <div className="account-section">
            <h2>My applications</h2>
            {applications.length === 0 ? (
              <p className="muted-text">No application memberships are active.</p>
            ) : (
              <div className="item-list">
                {applications.map((membership) => (
                  <div className="item-row" key={membership.id}>
                    <span>
                      {membership.application.name}
                      <span className="item-meta"> · {membership.status}</span>
                    </span>
                    <button
                      className="secondary-button"
                      type="button"
                      onClick={() => void handleLeaveApplication(membership.id)}
                      disabled={membership.status === 'left' || membership.status === 'deleted'}
                    >
                      Leave
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="account-section">
            <h2>Products</h2>
            {products.length === 0 ? (
              <p className="muted-text">No public products are available yet.</p>
            ) : (
              <div className="item-list">
                {products.map((product) => (
                  <div className="item-row" key={`${product.sku}-${product.version}`}>
                    <span>{product.name}</span>
                    <span className="item-meta">
                      {product.sku} · v{product.version}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="account-section">
            <h2>Your platform access</h2>
            {entitlements.length === 0 ? (
              <p className="muted-text">No active entitlements.</p>
            ) : (
              <div className="item-list">
                {entitlements.map((entitlement, index) => (
                  <div
                    className="item-row"
                    key={`${entitlement.feature}-${entitlement.sourceProduct}-${index}`}
                  >
                    <span>{entitlement.feature}</span>
                    <span className="item-meta">
                      {entitlement.sourceProduct}
                      {entitlement.expiresAt
                        ? ` · expires ${new Date(entitlement.expiresAt).toLocaleDateString()}`
                        : ' · permanent'}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="account-section">
            <h2>Redeem a code</h2>
            <form className="inline-form" onSubmit={(event) => void handleRedeem(event)}>
              <label className="sr-only" htmlFor="redemption-code">
                Redemption code
              </label>
              <input
                id="redemption-code"
                value={redemptionCode}
                onChange={(event) => setRedemptionCode(event.target.value)}
                placeholder="Enter your redemption code"
                autoComplete="off"
              />
              <button className="primary-button" type="submit" disabled={isRedeeming}>
                {isRedeeming ? 'Redeeming…' : 'Redeem'}
              </button>
            </form>
          </div>

          <div className="account-section danger-section">
            <h2>Delete account</h2>
            <p className="muted-text">
              This starts the recoverable platform deletion workflow. Confirm to continue.
            </p>
            <form className="deletion-form" onSubmit={(event) => void handleDeletion(event)}>
              <label className="checkbox-row">
                <input
                  type="checkbox"
                  checked={deletionConfirmed}
                  onChange={(event) => setDeletionConfirmed(event.target.checked)}
                />{' '}
                I understand this will sign me out and schedule account deletion.
              </label>
              <button
                className="danger-button"
                type="submit"
                disabled={isDeleting || !deletionConfirmed}
              >
                {isDeleting ? 'Submitting…' : 'Request account deletion'}
              </button>
            </form>
          </div>

          <button className="secondary-button" type="button" onClick={() => void handleLogout()}>
            Sign out
          </button>
        </section>
      </main>
    );
  }

  return (
    <main className="account-shell">
      <section className="account-card" aria-labelledby="login-title">
        <p className="eyebrow">AisenHub Account</p>
        <h1 id="login-title">One account for your tools.</h1>
        <p className="supporting-text">
          Authorize securely with OAuth to continue across the AisenHub platform.
        </p>
        {message && (
          <p className="error-text" role="alert">
            {message}
          </p>
        )}
        <form className="login-form" onSubmit={(event) => void handleSubmit(event)}>
          <button className="primary-button" type="submit" disabled={viewState === 'signing_in'}>
            {viewState === 'signing_in' ? 'Opening secure sign-in…' : 'Continue with AisenHub'}
          </button>
        </form>
      </section>
    </main>
  );
}
