import { useTable } from '@refinedev/antd';
import { Card, Typography } from 'antd';
import type { HttpError } from '@refinedev/core';
import type { AdminAuditLogSummary } from '@aisenhub/contracts';
import { DateTimeDisplay } from '@aisenhub/design-system';

import { AuditTimeline } from '../components/AuditTimeline';
import { DataTable } from '../components/DataTable';
import { FilterBar } from '../components/FilterBar';

export function AuditLogsPage() {
  const { searchFormProps, tableProps, tableQuery } = useTable<
    AdminAuditLogSummary,
    HttpError,
    { search?: string }
  >({
    resource: 'auditLogs',
    syncWithLocation: true,
    pagination: { pageSize: 25 },
    sorters: { initial: [{ field: 'createdAt', order: 'desc' }] },
    queryOptions: { retry: 1, retryDelay: 250 },
    onSearch: ({ search }) =>
      search?.trim() ? [{ field: 'search', operator: 'contains', value: search.trim() }] : [],
  });

  const items = Array.from(tableProps.dataSource ?? []) as unknown as AdminAuditLogSummary[];

  return (
    <Card>
      <Typography.Title level={2}>Audit logs</Typography.Title>
      <Typography.Paragraph type="secondary">
        Append-only operational history. Request IDs and before/after summaries come from the
        Platform Backend projection.
      </Typography.Paragraph>
      <FilterBar resource="auditLogs" formProps={searchFormProps} />
      <DataTable
        tableProps={{
          ...tableProps,
          columns: [
            { dataIndex: 'action', key: 'action', sorter: true, title: 'Action' },
            { dataIndex: 'targetType', key: 'targetType', sorter: true, title: 'Target' },
            { dataIndex: 'targetId', key: 'targetId', title: 'Target ID' },
            { dataIndex: 'reason', key: 'reason', title: 'Reason' },
            {
              dataIndex: 'createdAt',
              key: 'createdAt',
              sorter: true,
              title: 'Created',
              render: (value: string) => <DateTimeDisplay value={value} />,
            },
          ],
        }}
        isError={tableQuery.isError}
        error={tableQuery.error}
        onRetry={() => void tableQuery.refetch()}
        emptyDescription="No audit events match the current filters."
      />
      {items.length > 0 ? (
        <Card size="small" title="Recent event timeline" style={{ marginTop: 20 }}>
          <AuditTimeline items={items} />
        </Card>
      ) : null}
    </Card>
  );
}
