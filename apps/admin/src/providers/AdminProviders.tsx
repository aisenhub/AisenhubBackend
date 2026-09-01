import type { ReactNode } from 'react';
import { App as AntApp, ConfigProvider } from 'antd';

import { adminTheme } from '../app/theme';

type AdminProvidersProps = {
  children: ReactNode;
};

export function AdminProviders({ children }: AdminProvidersProps) {
  return (
    <ConfigProvider theme={adminTheme}>
      <AntApp>{children}</AntApp>
    </ConfigProvider>
  );
}
