import type { AdminSessionResponse } from '@aisenhub/contracts';

export type AdminSessionStore = {
  getSession: () => AdminSessionResponse | null;
  setSession: (session: AdminSessionResponse) => void;
  clear: () => void;
};

export function createAdminSessionStore(): AdminSessionStore {
  let session: AdminSessionResponse | null = null;

  return {
    getSession: () => session,
    setSession: (nextSession) => {
      session = nextSession;
    },
    clear: () => {
      session = null;
    },
  };
}
