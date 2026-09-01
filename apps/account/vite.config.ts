import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

const e2eProxyTarget = process.env.E2E_PROXY_TARGET;
const e2eProxyOrigin = process.env.E2E_PROXY_ORIGIN ?? 'http://localhost:5173';

export default defineConfig({
  plugins: [react()],
  ...(e2eProxyTarget
    ? {
        server: {
          proxy: {
            '/functions': {
              target: e2eProxyTarget,
              changeOrigin: false,
              configure: (proxy) => {
                proxy.on('proxyReq', (proxyRequest) => {
                  proxyRequest.setHeader('origin', e2eProxyOrigin);
                });
              },
            },
          },
        },
      }
    : {}),
});
