import { Refine } from '@refinedev/core';
import { RefineThemes } from '@refinedev/antd';
import { ConfigProvider, Layout, Typography } from 'antd';
import { BrowserRouter } from 'react-router-dom';

import '@refinedev/antd/dist/reset.css';

export function App() {
  return (
    <ConfigProvider theme={RefineThemes.Blue}>
      <BrowserRouter>
        <Refine options={{ syncWithLocation: true }}>
          <Layout style={{ minHeight: '100vh' }}>
            <Layout.Header>
              <Typography.Text style={{ color: '#fff' }}>AisenHub Operations</Typography.Text>
            </Layout.Header>
            <Layout.Content style={{ padding: 24 }}>
              <Typography.Title level={2}>Admin foundation</Typography.Title>
              <Typography.Paragraph>
                Refine and Ant Design are configured for the platform operations console.
              </Typography.Paragraph>
            </Layout.Content>
          </Layout>
        </Refine>
      </BrowserRouter>
    </ConfigProvider>
  );
}
