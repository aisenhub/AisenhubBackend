import { App as AntApp, Avatar, Badge, Layout, Menu, Space, Typography } from 'antd';
import type { ReactNode } from 'react';

const navigationItems = [
  { key: 'overview', label: 'Overview' },
  { key: 'catalog', label: 'Catalog' },
  { key: 'customers', label: 'Customers' },
  { key: 'operations', label: 'Operations' },
];

type AdminLayoutProps = {
  children: ReactNode;
};

export function AdminLayout({ children }: AdminLayoutProps) {
  return (
    <AntApp>
      <Layout style={{ minHeight: '100vh' }}>
        <Layout.Sider breakpoint="lg" collapsedWidth="0" theme="dark">
          <div style={{ padding: '24px 20px 16px' }}>
            <Typography.Title level={4} style={{ color: '#fff', margin: 0 }}>
              AisenHub
            </Typography.Title>
            <Typography.Text style={{ color: 'rgba(255,255,255,.62)', fontSize: 12 }}>
              Operations console
            </Typography.Text>
          </div>
          <Menu
            defaultSelectedKeys={['overview']}
            items={navigationItems}
            mode="inline"
            theme="dark"
          />
        </Layout.Sider>
        <Layout>
          <Layout.Header
            style={{
              alignItems: 'center',
              background: '#fff',
              borderBottom: '1px solid #dbe5e8',
              display: 'flex',
              justifyContent: 'space-between',
              padding: '0 28px',
            }}
          >
            <div>
              <Typography.Text type="secondary">Platform operations</Typography.Text>
              <Typography.Title level={3} style={{ margin: 0 }}>
                Overview
              </Typography.Title>
            </div>
            <Space size="middle">
              <Badge dot status="success" text="Local environment" />
              <Avatar style={{ backgroundColor: '#176b87' }}>AH</Avatar>
            </Space>
          </Layout.Header>
          <Layout.Content style={{ padding: 28 }}>{children}</Layout.Content>
          <Layout.Footer
            style={{ background: 'transparent', color: '#58717b', textAlign: 'center' }}
          >
            AisenHub Platform · Operations workspace
          </Layout.Footer>
        </Layout>
      </Layout>
    </AntApp>
  );
}
