import { Card, Flex, Space, Typography } from 'antd';
import { Link } from 'react-router-dom';

export function CatalogPage() {
  return (
    <Flex vertical gap={16}>
      <div>
        <Typography.Title level={2} style={{ marginBottom: 4 }}>
          Catalog
        </Typography.Title>
        <Typography.Paragraph type="secondary">
          Manage draft catalog records and inspect the immutable Product 360 view. Business state
          transitions are available only through explicit commands.
        </Typography.Paragraph>
      </div>
      <Card title="Catalog surfaces">
        <Space wrap>
          <Link to="/catalog/products">Products</Link>
          <Link to="/catalog/product-versions">Product versions</Link>
          <Link to="/catalog/prices">Prices</Link>
          <Link to="/catalog/origins">Origins</Link>
          <Link to="/catalog/features">Features</Link>
        </Space>
      </Card>
    </Flex>
  );
}
