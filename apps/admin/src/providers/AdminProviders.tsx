import type { ReactNode } from 'react';
import { ConfigProvider } from 'antd';

import { adminTheme } from '../app/theme';

type AdminProvidersProps = {
  children: ReactNode;
};

export function AdminProviders({ children }: AdminProvidersProps) {
  return <ConfigProvider theme={adminTheme}>{children}</ConfigProvider>;
}
