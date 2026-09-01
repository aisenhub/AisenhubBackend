import { describe, expect, it } from 'vitest';

import { getCommandErrorPresentation } from './DangerousActionDialog';
import { getMfaRequirementState } from './MfaRequirement';

describe('DangerousActionDialog safety metadata', () => {
  it('requires an elevated verified session for a high-risk action', () => {
    expect(getMfaRequirementState({ aal: 'aal1', mfaState: 'required' })).toMatchObject({
      status: 'warning',
      label: 'MFA required',
    });
    expect(getMfaRequirementState({ aal: 'aal2', mfaState: 'verified' })).toMatchObject({
      status: 'success',
      label: 'MFA verified',
    });
  });

  it('maps stable errors without exposing internal details', () => {
    expect(
      getCommandErrorPresentation({
        code: 'INVALID_STATE_TRANSITION',
        status: 409,
        requestId: '00000000-0000-4000-8000-000000000099',
      }),
    ).toEqual({
      title: 'State conflict',
      description: 'The record changed before this operation completed. Refresh and try again.',
      requestId: '00000000-0000-4000-8000-000000000099',
    });
    expect(
      JSON.stringify(
        getCommandErrorPresentation({ status: 500, message: 'SQL table stack trace secret' }),
      ),
    ).not.toMatch(/SQL|table|stack|secret/i);
  });
});
