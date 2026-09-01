import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

const e2eProxyTarget = process.env.E2E_PROXY_TARGET;

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
                  if (!proxyRequest.getHeader('origin')) {
                    proxyRequest.setHeader('origin', 'http://localhost:5173');
                  }
                });
              },
            },
          },
        },
      }
    : {}),
});
