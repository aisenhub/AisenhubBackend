import { Button, Form, Input, Select, Space } from 'antd';
import type { FormProps } from 'antd';
import { useEffect, useState } from 'react';

import { loadSavedFilters, saveCurrentFilter } from '../../../providers/saved-filters';

export type FilterBarProps = {
  resource: string;
  formProps: FormProps<{ search?: string; status?: string }>;
  statusOptions?: readonly string[];
};

export function FilterBar({ resource, formProps, statusOptions = [] }: FilterBarProps) {
  const [createdForm] = Form.useForm();
  const form = formProps.form ?? createdForm;
  const selectedStatus = Form.useWatch('status', form);
  const [savedFilters, setSavedFilters] = useState(() => loadSavedFilters(resource));

  useEffect(() => {
    setSavedFilters(loadSavedFilters(resource));
  }, [resource]);

  return (
    <Form {...formProps} form={form} layout="inline" style={{ marginBottom: 20 }}>
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
        <Select
          aria-label="Saved views"
          allowClear
          placeholder="Saved view"
          style={{ minWidth: 150 }}
          onChange={(id: string | undefined) => {
            const saved = savedFilters.find((item) => item.id === id);
            if (!saved) return;
            form.setFieldValue('status', saved.status);
            form.submit();
          }}
          options={savedFilters.map((saved) => ({ label: saved.label, value: saved.id }))}
        />
        <Button
          onClick={() => {
            const saved = saveCurrentFilter({ resource, status: selectedStatus });
            if (saved) setSavedFilters(loadSavedFilters(resource));
          }}
          disabled={statusOptions.length === 0 && selectedStatus === undefined}
        >
          Save view
        </Button>
        <Button htmlType="submit" type="primary">
          Apply filters
        </Button>
      </Space>
    </Form>
  );
}
