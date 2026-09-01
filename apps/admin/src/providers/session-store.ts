import type { AdminSessionResponse } from '@aisenhub/contracts';

export type AdminSessionStore = {
  getSession: () => AdminSessionResponse | null;
  setSession: (session: AdminSessionResponse) => void;
  getCsrfToken: () => string | undefined;
  setCsrfToken: (token: string | undefined) => void;
  clear: () => void;
};

export function createAdminSessionStore(): AdminSessionStore {
  let session: AdminSessionResponse | null = null;
  let csrfToken: string | undefined;

  return {
    getSession: () => session,
    setSession: (nextSession) => {
      session = nextSession;
    },
    getCsrfToken: () => csrfToken,
    setCsrfToken: (nextToken) => {
      csrfToken = nextToken;
    },
    clear: () => {
      session = null;
      csrfToken = undefined;
    },
  };
}
