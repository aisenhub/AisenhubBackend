import type { AdminGeneratedRedemptionCode } from '@aisenhub/contracts';

const consumedResponses = new WeakSet<object>();

export function generatedCodesFileContent(codes: readonly AdminGeneratedRedemptionCode[]): string {
  const plaintextCodes = codes
    .map((code) => code.code)
    .filter((code): code is string => Boolean(code));
  if (plaintextCodes.length !== codes.length) {
    throw new Error('Only a fresh code generation response can be downloaded.');
  }
  return `${plaintextCodes.join('\n')}\n`;
}

export function downloadGeneratedCodesOnce(
  response: object,
  codes: readonly AdminGeneratedRedemptionCode[],
): boolean {
  if (consumedResponses.has(response)) return false;
  consumedResponses.add(response);

  const blob = new Blob([generatedCodesFileContent(codes)], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = 'aisenhub-redemption-codes.txt';
  anchor.click();
  URL.revokeObjectURL(url);
  return true;
}
