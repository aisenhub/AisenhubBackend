import { Alert, Button, Space, Typography } from 'antd';
import { useCallback, useState } from 'react';
import type { AdminRedemptionBatchSummary } from '@aisenhub/contracts';

import { EntityStatus } from '@aisenhub/design-system';
import { DangerousActionDialog, type DangerousActionResult } from '../../../components';
import { useAdminCommand } from '../../../hooks/use-admin-command';
import { adminRuntime } from '../../../providers/admin-runtime';
import { ResourcePage } from '../../operations/pages/ResourcePage';
import { downloadGeneratedCodesOnce } from '../components/secure-download';

type CommandKind = 'generate' | 'pause' | 'close';

export function RedemptionBatchesPage() {
  const session = adminRuntime.session.getSession();
  const canMutate = session?.role === 'owner' || session?.role === 'admin';
  const [selected, setSelected] = useState<{
    batch: AdminRedemptionBatchSummary;
    kind: CommandKind;
  } | null>(null);
  const invokeGenerate = useCallback(
    (
      input: { reason: string; confirmation: true; quantity: number },
      options: Parameters<typeof adminRuntime.commands.generateRedemptionCodes>[2],
    ) =>
      selected
        ? adminRuntime.commands.generateRedemptionCodes(selected.batch.id, input, options)
        : Promise.reject(new Error('A batch is required.')),
    [selected],
  );
  const generateCommand = useAdminCommand(invokeGenerate, { retainResult: false });

  const onConfirm = async (values: {
    reason: string;
    confirmation: true;
  }): Promise<DangerousActionResult> => {
    if (!selected) throw new Error('A batch is required.');
    if (selected.kind === 'generate') {
      const result = await generateCommand.execute({
        ...values,
        quantity: selected.batch.quantity,
      });
      downloadGeneratedCodesOnce(result.data, result.data.codes);
      return { requestId: result.requestId, auditLogId: result.data.auditLogId };
    }
    const result =
      selected.kind === 'pause'
        ? await adminRuntime.commands.pauseRedemptionBatch(selected.batch.id, values)
        : await adminRuntime.commands.closeRedemptionBatch(selected.batch.id, values);
    return { requestId: result.requestId, auditLogId: result.data.auditLogId };
  };

  return (
    <ResourcePage<AdminRedemptionBatchSummary>
      resource="redemptionBatches"
      title="Redemption batches"
      description="Operate batches through audited commands. Full codes are available only in the immediate generation download."
      emptyDescription="No Redemption batches match the current filters."
      initialSort="createdAt"
      statusOptions={['draft', 'active', 'paused', 'closed']}
      columns={[
        { dataIndex: 'name', key: 'name', sorter: true, title: 'Batch' },
        { dataIndex: 'productSku', key: 'productSku', title: 'Product' },
        { dataIndex: 'quantity', key: 'quantity', title: 'Quantity' },
        { dataIndex: 'issuedCount', key: 'issuedCount', title: 'Issued' },
        { dataIndex: 'redeemedCount', key: 'redeemedCount', title: 'Redeemed' },
        {
          dataIndex: 'status',
          key: 'status',
          sorter: true,
          title: 'Status',
          render: (status: string) => <EntityStatus status={status} />,
        },
        {
          key: 'actions',
          title: 'Commands',
          render: (_value: unknown, batch: AdminRedemptionBatchSummary) => (
            <Space>
              {canMutate && batch.status === 'draft' ? (
                <Button type="link" onClick={() => setSelected({ batch, kind: 'generate' })}>
                  Generate
                </Button>
              ) : null}
              {canMutate && batch.status === 'active' ? (
                <Button type="link" onClick={() => setSelected({ batch, kind: 'pause' })}>
                  Pause
                </Button>
              ) : null}
              {canMutate && (batch.status === 'active' || batch.status === 'paused') ? (
                <Button type="link" danger onClick={() => setSelected({ batch, kind: 'close' })}>
                  Close
                </Button>
              ) : null}
            </Space>
          ),
        },
      ]}
    >
      {generateCommand.state.error ? (
        <Alert
          type="error"
          message="Code generation failed"
          description="Retry with the same operation if the request may have timed out."
        />
      ) : null}
      <Typography.Text type="secondary">
        History exposes hints only; it never reconstructs a complete code.
      </Typography.Text>
      {selected ? (
        <DangerousActionDialog
          open
          title={`${selected.kind === 'generate' ? 'Generate codes' : selected.kind === 'pause' ? 'Pause batch' : 'Close batch'} · ${selected.batch.name}`}
          actionLabel={
            selected.kind === 'generate'
              ? 'Generate and download'
              : selected.kind === 'pause'
                ? 'Pause batch'
                : 'Close batch'
          }
          target={{
            label: selected.batch.name,
            id: selected.batch.id,
            currentState: selected.batch.status,
            targetState: selected.kind === 'generate' ? 'active' : selected.kind,
            impactSummary:
              selected.kind === 'generate'
                ? `Create ${selected.batch.quantity} one-time codes and download the fresh response once.`
                : 'This changes the batch lifecycle state for future operations.',
          }}
          assurance={{
            aal: session?.aal ?? 'aal1',
            mfaState: session?.mfaState ?? 'required',
          }}
          onConfirm={onConfirm}
          onCancel={() => setSelected(null)}
        />
      ) : null}
    </ResourcePage>
  );
}
