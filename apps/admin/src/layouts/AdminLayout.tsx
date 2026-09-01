import { Avatar, Badge, Layout, Menu, Space, Typography } from 'antd';
import { useCan } from '@refinedev/core';
import type { ReactNode } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';

import { adminModules, getAdminModule } from '../app/module-registry';

type AdminLayoutProps = {
  children: ReactNode;
};

export function AdminLayout({ children }: AdminLayoutProps) {
  const location = useLocation();
  const navigate = useNavigate();
  const selectedKey = location.pathname.split('/')[1] || 'overview';
  const applicationAccess = useCan({ resource: 'applications', action: 'list' });
  const auditAccess = useCan({ resource: 'auditLogs', action: 'list' });

  const isModuleVisible = (module: (typeof adminModules)[number]) => {
    if (module.key === 'applications') return applicationAccess.data?.can ?? false;
    if (module.key === 'auditLogs') return auditAccess.data?.can ?? false;
    return true;
  };

  return (
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
          items={adminModules.filter(isModuleVisible).map((module) => ({
            key: module.key,
            label: module.available ? module.label : `${module.label} (coming soon)`,
            disabled: !module.available,
          }))}
          mode="inline"
          onClick={({ key }) => {
            const module = adminModules.find((item) => item.key === key);
            if (module?.available) navigate(module.path);
          }}
          selectedKeys={[selectedKey]}
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
              {getAdminModule(`/${selectedKey}`)?.label ?? 'Operations'}
            </Typography.Title>
          </div>
          <Space size="middle">
            <Badge dot status="success" text="Local environment" />
            <Avatar style={{ backgroundColor: '#176b87' }}>AH</Avatar>
          </Space>
        </Layout.Header>
        <Layout.Content style={{ padding: 28 }}>{children}</Layout.Content>
        <Layout.Footer style={{ background: 'transparent', color: '#58717b', textAlign: 'center' }}>
          AisenHub Platform · Operations workspace
        </Layout.Footer>
      </Layout>
    </Layout>
  );
}
