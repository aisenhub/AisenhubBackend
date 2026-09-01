import { describe, expect, it } from 'vitest';
import {
  generateRedemptionCode,
  generateRedemptionCodes,
  redemptionPepperFromEnv,
  toRedemptionCodeRecord,
} from '../supabase/functions/_shared/redemption-code';

function counterRandom(): (target: Uint8Array) => void {
  let state = 0x12345678;
  return (target) => {
    for (let index = 0; index < target.length; index += 1) {
      state = (Math.imul(state, 1_664_525) + 1_013_904_223) >>> 0;
      target[index] = state & 0xff;
    }
  };
}

describe('redemption code generation', () => {
  it('generates unique high-entropy easy-entry codes', async () => {
    const codes = await generateRedemptionCodes('AH-TEST', 100, 'local-only-test-pepper', 1);

    expect(codes).toHaveLength(100);
    expect(new Set(codes.map((code) => code.codeHash)).size).toBe(100);
    expect(codes[0]?.plaintext).toMatch(/^AH-TEST(?:-[A-Z2-9]{4}){6}-[A-Z2-9]{2}$/);
    expect(codes[0]?.codeHash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('returns a hint and persistence record without plaintext', async () => {
    const material = await generateRedemptionCode(
      'AH-TEST',
      'local-only-test-pepper',
      3,
      counterRandom(),
    );
    const record = toRedemptionCodeRecord('batch-001', material);

    expect(material.codeHint).toContain('AH-TEST-****-');
    expect(material.codeHint).not.toContain(material.plaintext);
    expect(record).toEqual({
      batchId: 'batch-001',
      codeHash: material.codeHash,
      codeHint: material.codeHint,
      pepperVersion: 3,
      status: 'issued',
    });
    expect(record).not.toHaveProperty('plaintext');
  });

  it('binds the digest to the configured pepper', async () => {
    const first = await generateRedemptionCode('AH-TEST', 'pepper-a', 1, counterRandom());
    const second = await generateRedemptionCode('AH-TEST', 'pepper-b', 1, counterRandom());

    expect(first.plaintext).toBe(second.plaintext);
    expect(first.codeHash).not.toBe(second.codeHash);
  });

  it('rejects missing or invalid generation configuration', async () => {
    await expect(generateRedemptionCode('AH-TEST', '', 1, counterRandom())).rejects.toThrow(
      'pepper',
    );
    await expect(
      generateRedemptionCodes('AH-TEST', 0, 'pepper', 1, counterRandom()),
    ).rejects.toThrow('count');
    await expect(generateRedemptionCode('ah-test', 'pepper', 1, counterRandom())).rejects.toThrow(
      'prefix',
    );
    await expect(generateRedemptionCode('AH-TEST', 'pepper', 0, counterRandom())).rejects.toThrow(
      'pepper version',
    );
    expect(() =>
      toRedemptionCodeRecord('', {
        plaintext: 'unused',
        codeHash: 'a'.repeat(64),
        codeHint: 'AH-TEST-****-ABCD',
        pepperVersion: 1,
      }),
    ).toThrow('batch ID');
  });

  it('loads pepper only from server-side environment access', () => {
    expect(
      redemptionPepperFromEnv(
        (name) =>
          ({
            REDEMPTION_PEPPER: 'local-only-test-pepper',
            REDEMPTION_PEPPER_VERSION: '2',
          })[name],
      ),
    ).toEqual({ pepper: 'local-only-test-pepper', pepperVersion: 2 });
    expect(() => redemptionPepperFromEnv(() => undefined)).toThrow('REDEMPTION_PEPPER');
  });
});
