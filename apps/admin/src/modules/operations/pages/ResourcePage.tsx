import { Card, Flex, Typography } from 'antd';
import { useTable } from '@refinedev/antd';
import type { BaseRecord, HttpError } from '@refinedev/core';
import type { TableProps } from 'antd';

import { DataTable } from '../components/DataTable';
import { FilterBar } from '../components/FilterBar';

type SearchForm = { search?: string; status?: string };

export type ResourcePageProps<TRecord extends BaseRecord> = {
  resource: string;
  title: string;
  description: string;
  emptyDescription: string;
  columns: TableProps<TRecord>['columns'];
  statusOptions?: readonly string[];
  initialSort: string;
  children?: React.ReactNode;
};

export function ResourcePage<TRecord extends BaseRecord>({
  resource,
  title,
  description,
  emptyDescription,
  columns,
  statusOptions,
  initialSort,
  children,
}: ResourcePageProps<TRecord>) {
  const { searchFormProps, tableProps, tableQuery } = useTable<TRecord, HttpError, SearchForm>({
    resource,
    syncWithLocation: true,
    pagination: { pageSize: 25 },
    sorters: { initial: [{ field: initialSort, order: 'desc' }] },
    onSearch: (values) => {
      const filters = [];
      if (values.search?.trim()) {
        filters.push({
          field: 'search',
          operator: 'contains' as const,
          value: values.search.trim(),
        });
      }
      if (values.status) {
        filters.push({ field: 'status', operator: 'eq' as const, value: values.status });
      }
      return filters;
    },
  });

  return (
    <Flex vertical gap={16}>
      <div>
        <Typography.Title level={2} style={{ marginBottom: 4 }}>
          {title}
        </Typography.Title>
        <Typography.Paragraph type="secondary" style={{ marginBottom: 0 }}>
          {description}
        </Typography.Paragraph>
      </div>
      <Card>
        <FilterBar resource={resource} formProps={searchFormProps} statusOptions={statusOptions} />
        {children}
        <DataTable
          tableProps={{ ...tableProps, columns }}
          isError={tableQuery.isError}
          error={tableQuery.error}
          emptyDescription={emptyDescription}
        />
      </Card>
    </Flex>
  );
}
