import { afterEach, describe, expect, it, vi } from 'vitest';

import { downloadGeneratedCodesOnce, generatedCodesFileContent } from './secure-download';

afterEach(() => vi.unstubAllGlobals());

describe('one-time Redemption code download', () => {
  it('accepts only fresh plaintext materials and consumes one response once', () => {
    const response = {};
    const anchor = { click: vi.fn(), href: '', download: '' };
    vi.stubGlobal('document', { createElement: vi.fn(() => anchor) });
    vi.stubGlobal('URL', {
      createObjectURL: vi.fn(() => 'blob:local'),
      revokeObjectURL: vi.fn(),
    });

    const codes = [
      {
        codeId: '00000000-0000-4000-8000-000000000001',
        code: 'AH-LOCAL-ABCD-2345',
        codeHint: 'AH-LOCAL-****-2345',
      },
    ];
    expect(generatedCodesFileContent(codes)).toBe('AH-LOCAL-ABCD-2345\n');
    expect(downloadGeneratedCodesOnce(response, codes)).toBe(true);
    expect(downloadGeneratedCodesOnce(response, codes)).toBe(false);
    expect(anchor.click).toHaveBeenCalledOnce();
  });

  it('rejects safe retry responses without complete plaintext', () => {
    expect(() =>
      generatedCodesFileContent([
        {
          codeId: '00000000-0000-4000-8000-000000000002',
          codeHint: 'AH-LOCAL-****-2345',
        },
      ]),
    ).toThrow('fresh code generation response');
  });
});
