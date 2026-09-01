import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';

import {
  createPlatformClient,
  PlatformClientError,
  type PlatformResponse,
} from '@aisenhub/platform-client';
import type { SessionResponse } from '@aisenhub/contracts';

import { AccountAuthClient, AccountAuthError } from './auth';
import './styles.css';

type ViewState = 'loading' | 'signed_out' | 'signing_in' | 'authenticated' | 'error';
type AuthenticatedSession = Extract<SessionResponse, { authenticated: true }>;

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL ?? 'http://127.0.0.1:54321';
const platformApiUrl =
  import.meta.env.VITE_PLATFORM_API_URL ?? 'http://127.0.0.1:54321/functions/v1/platform-api';

function readableError(error: unknown): string {
  if (error instanceof AccountAuthError) return error.message;
  if (error instanceof PlatformClientError) {
    if (error.code === 'AUTHENTICATION_REQUIRED') {
      return 'Your session has expired. Please sign in again.';
    }
    return 'Something went wrong. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}

function isAuthenticated(
  response: PlatformResponse<SessionResponse>,
): response is PlatformResponse<AuthenticatedSession> {
  return response.data.authenticated;
}

export function App() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [viewState, setViewState] = useState<ViewState>('loading');
  const [message, setMessage] = useState<string | null>(null);
  const [session, setSession] = useState<AuthenticatedSession | null>(null);
  const csrfTokenRef = useRef<string | undefined>(undefined);
  const auth = useMemo(
    () =>
      new AccountAuthClient({
        supabaseUrl,
        anonKey: import.meta.env.VITE_SUPABASE_ANON_KEY ?? '',
      }),
    [],
  );
  const client = useMemo(
    () =>
      createPlatformClient({
        baseUrl: platformApiUrl,
        appSlug: 'account',
        csrfToken: () => csrfTokenRef.current,
      }),
    [],
  );

  useEffect(() => {
    let active = true;
    client
      .getSession()
      .then((response) => {
        if (!active) return;
        if (isAuthenticated(response)) {
          setSession(response.data);
          csrfTokenRef.current = response.data.csrfToken;
          setViewState('authenticated');
        } else {
          setViewState('signed_out');
        }
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
      const authSession = await auth.signInWithPassword(email, password);
      const exchanged = await client.exchangeSession(authSession.accessToken);
      setSession(exchanged.data);
      csrfTokenRef.current = exchanged.data.csrfToken;
      setPassword('');
      setViewState('authenticated');
    } catch (error: unknown) {
      setMessage(readableError(error));
      setViewState('signed_out');
    }
  }

  async function handleLogout() {
    setMessage(null);
    try {
      await client.logout();
    } catch (error: unknown) {
      setMessage(readableError(error));
      return;
    }
    auth.signOut();
    csrfTokenRef.current = undefined;
    setSession(null);
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
      <main className="account-shell">
        <section className="account-card" aria-labelledby="welcome-title">
          <p className="eyebrow">AisenHub Account</p>
          <h1 id="welcome-title">
            Welcome back{session.identity.displayName ? `, ${session.identity.displayName}` : ''}.
          </h1>
          <p className="supporting-text">
            Your platform session is active. Your security token remains in memory on this page.
          </p>
          {message && (
            <p className="error-text" role="alert">
              {message}
            </p>
          )}
          <button className="primary-button" type="button" onClick={handleLogout}>
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
        <p className="supporting-text">Sign in to continue across the AisenHub platform.</p>
        <form className="login-form" onSubmit={handleSubmit}>
          <div className="field-group">
            <label htmlFor="email">Email address</label>
            <input
              id="email"
              name="email"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
          </div>
          <div className="field-group">
            <label htmlFor="password">Password</label>
            <input
              id="password"
              name="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </div>
          {message && (
            <p className="error-text" role="alert">
              {message}
            </p>
          )}
          <button className="primary-button" type="submit" disabled={viewState === 'signing_in'}>
            {viewState === 'signing_in' ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </section>
    </main>
  );
}
