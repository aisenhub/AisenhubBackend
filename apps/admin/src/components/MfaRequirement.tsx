import { Alert, Space, Tag, Typography } from 'antd';

export type AdminAssuranceState = {
  readonly aal: 'aal1' | 'aal2';
  readonly mfaState: 'not_required' | 'required' | 'verified';
};

export type MfaRequirementState = {
  readonly status: 'success' | 'warning';
  readonly label: string;
  readonly description: string;
};

export function getMfaRequirementState(state: AdminAssuranceState): MfaRequirementState {
  if (state.aal === 'aal2' && state.mfaState === 'verified') {
    return {
      status: 'success',
      label: 'MFA verified',
      description: 'This session meets the AAL2 requirement for the operation.',
    };
  }
  return {
    status: 'warning',
    label: 'MFA required',
    description: 'Complete MFA elevation before submitting this high-risk operation.',
  };
}

export type MfaRequirementProps = AdminAssuranceState & {
  readonly compact?: boolean;
};

export function MfaRequirement({ aal, mfaState, compact = false }: MfaRequirementProps) {
  const state = getMfaRequirementState({ aal, mfaState });
  if (compact) {
    return <Tag color={state.status === 'success' ? 'success' : 'warning'}>{state.label}</Tag>;
  }
  return (
    <Alert
      type={state.status}
      showIcon
      message={
        <Space size="small">
          <Typography.Text strong>{state.label}</Typography.Text>
          <Typography.Text type="secondary">AAL {aal === 'aal2' ? '2' : '1'}</Typography.Text>
        </Space>
      }
      description={state.description}
    />
  );
}
