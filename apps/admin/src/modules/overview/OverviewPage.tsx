import { Card, Col, Descriptions, Row, Tag, Typography } from 'antd';

export function OverviewPage() {
  return (
    <Row gutter={[16, 16]}>
      <Col xs={24} xl={16}>
        <Card
          title="Workspace readiness"
          extra={<Tag color="green">Foundation ready</Tag>}
          styles={{ body: { padding: 24 } }}
        >
          <Typography.Paragraph style={{ color: '#58717b', marginBottom: 0 }}>
            The Admin shell is connected to the Refine and Ant Design foundation. Domain resources,
            permission providers, and backend data providers are added in their dedicated tasks.
          </Typography.Paragraph>
        </Card>
      </Col>
      <Col xs={24} xl={8}>
        <Card title="Foundation map">
          <Descriptions column={1} size="small">
            <Descriptions.Item label="UI system">Ant Design</Descriptions.Item>
            <Descriptions.Item label="Admin framework">Refine</Descriptions.Item>
            <Descriptions.Item label="Data boundary">/v1/admin/*</Descriptions.Item>
            <Descriptions.Item label="Business authority">Platform Backend</Descriptions.Item>
          </Descriptions>
        </Card>
      </Col>
    </Row>
  );
}
