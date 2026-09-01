import { useCallback, useRef, useState } from 'react';

import type {
  AdminCommandOptions,
  AdminCommandResult,
  AisenHubBusinessCommandClient,
} from '@aisenhub/admin-client';

export type AdminCommandInvoker<TInput, TOutput> = (
  input: TInput,
  options?: AdminCommandOptions,
) => Promise<AdminCommandResult<TOutput>>;

export type AdminCommandState<TOutput> = {
  readonly status: 'idle' | 'pending' | 'success' | 'error';
  readonly result: AdminCommandResult<TOutput> | null;
  readonly error: unknown;
  readonly requestId?: string;
  readonly idempotencyKey?: string;
};

export function useAdminCommand<TInput, TOutput>(invoke: AdminCommandInvoker<TInput, TOutput>) {
  const [state, setState] = useState<AdminCommandState<TOutput>>({
    status: 'idle',
    result: null,
    error: null,
  });
  const activePromise = useRef<Promise<AdminCommandResult<TOutput>> | null>(null);
  const lastIdempotencyKey = useRef<string | null>(null);

  const run = useCallback(
    (input: TInput, idempotencyKey: string) => {
      const promise = Promise.resolve().then(() => invoke(input, { idempotencyKey }));
      activePromise.current = promise;
      setState({ status: 'pending', result: null, error: null, idempotencyKey });
      void promise.then(
        (result) => {
          if (activePromise.current === promise) activePromise.current = null;
          lastIdempotencyKey.current = null;
          setState({
            status: 'success',
            result,
            error: null,
            requestId: result.requestId,
            idempotencyKey,
          });
        },
        (error: unknown) => {
          if (activePromise.current === promise) activePromise.current = null;
          lastIdempotencyKey.current = idempotencyKey;
          setState({
            status: 'error',
            result: null,
            error,
            requestId:
              typeof error === 'object' && error && 'requestId' in error
                ? String(error.requestId)
                : undefined,
            idempotencyKey,
          });
        },
      );
      return promise;
    },
    [invoke],
  );

  const execute = useCallback(
    (input: TInput) => {
      if (activePromise.current) return activePromise.current;
      const key = globalThis.crypto?.randomUUID();
      if (!key) return Promise.reject(new Error('An Idempotency-Key is required.'));
      lastIdempotencyKey.current = key;
      return run(input, key);
    },
    [run],
  );

  const retry = useCallback(
    (input: TInput) => {
      if (activePromise.current) return activePromise.current;
      const key = lastIdempotencyKey.current ?? globalThis.crypto?.randomUUID();
      if (!key) return Promise.reject(new Error('An Idempotency-Key is required.'));
      lastIdempotencyKey.current = key;
      return run(input, key);
    },
    [run],
  );

  const reset = useCallback(() => {
    if (activePromise.current) return;
    lastIdempotencyKey.current = null;
    setState({ status: 'idle', result: null, error: null });
  }, []);

  return { state, execute, retry, reset };
}

export type AdminCommandClientMethod = keyof AisenHubBusinessCommandClient;
