import { Button, Form, Input, Select, Space } from 'antd';
import type { FormProps } from 'antd';

export type FilterBarProps = {
  formProps: FormProps<{ search?: string }>;
  statusOptions?: readonly string[];
};

export function FilterBar({ formProps, statusOptions = [] }: FilterBarProps) {
  return (
    <Form {...formProps} layout="inline" style={{ marginBottom: 20 }}>
      <Space wrap>
        <Form.Item label="Search" name="search" style={{ marginBottom: 0 }}>
          <Input allowClear placeholder="Search this resource" style={{ width: 240 }} />
        </Form.Item>
        {statusOptions.length > 0 ? (
          <Form.Item label="Status" name="status" style={{ marginBottom: 0 }}>
            <Select allowClear placeholder="Any status" style={{ minWidth: 150 }}>
              {statusOptions.map((status) => (
                <Select.Option key={status} value={status}>
                  {status}
                </Select.Option>
              ))}
            </Select>
          </Form.Item>
        ) : null}
        <Button htmlType="submit" type="primary">
          Apply filters
        </Button>
      </Space>
    </Form>
  );
}
