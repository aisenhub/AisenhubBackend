const redemptionAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const codeEntropyLength = 26;
const maxCodesPerRequest = 10_000;

export type RedemptionCodeMaterial = {
  readonly plaintext: string;
  readonly codeHash: string;
  readonly codeHint: string;
  readonly pepperVersion: number;
};

export type RedemptionCodeRecord = {
  readonly batchId: string;
  readonly codeHash: string;
  readonly codeHint: string;
  readonly pepperVersion: number;
  readonly status: 'issued';
};

export type RandomValueSource = (target: Uint8Array) => void;

function defaultRandomValueSource(target: Uint8Array): void {
  const bytes = new Uint8Array(target.byteLength);
  crypto.getRandomValues(bytes);
  target.set(bytes);
}

function assertPepper(pepper: string): void {
  if (pepper.trim() === '') throw new Error('A redemption pepper is required.');
}

function assertPepperVersion(pepperVersion: number): void {
  if (!Number.isInteger(pepperVersion) || pepperVersion < 1 || pepperVersion > 32_767) {
    throw new Error('A valid redemption pepper version is required.');
  }
}

function assertPrefix(prefix: string): void {
  if (!/^[A-Z0-9]+(?:-[A-Z0-9]+)*$/.test(prefix)) {
    throw new Error('A valid uppercase redemption prefix is required.');
  }
}

function assertCount(count: number): void {
  if (!Number.isInteger(count) || count < 1 || count > maxCodesPerRequest) {
    throw new Error(`Redemption code count must be between 1 and ${maxCodesPerRequest}.`);
  }
}

function randomSegment(length: number, randomValues: RandomValueSource): string {
  const result: string[] = [];
  const limit = Math.floor(256 / redemptionAlphabet.length) * redemptionAlphabet.length;

  while (result.length < length) {
    const bytes = new Uint8Array(Math.max(32, length - result.length));
    randomValues(bytes);
    for (const byte of bytes) {
      if (byte >= limit) continue;
      result.push(redemptionAlphabet[byte % redemptionAlphabet.length]);
      if (result.length === length) break;
    }
  }

  return result.join('');
}

function formatCode(prefix: string, randomPart: string): string {
  const groups = randomPart.match(/.{1,4}/g) ?? [];
  return [prefix, ...groups].join('-');
}

function codeHint(prefix: string, randomPart: string): string {
  return `${prefix}-****-${randomPart.slice(-4)}`;
}

export async function hashRedemptionCode(value: string, pepper: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(pepper),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const digest = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

export async function generateRedemptionCode(
  prefix: string,
  pepper: string,
  pepperVersion: number,
  randomValues: RandomValueSource = defaultRandomValueSource,
): Promise<RedemptionCodeMaterial> {
  assertPrefix(prefix);
  assertPepper(pepper);
  assertPepperVersion(pepperVersion);

  const randomPart = randomSegment(codeEntropyLength, randomValues);
  const plaintext = formatCode(prefix, randomPart);
  return {
    plaintext,
    codeHash: await hashRedemptionCode(plaintext, pepper),
    codeHint: codeHint(prefix, randomPart),
    pepperVersion,
  };
}

export async function generateRedemptionCodes(
  prefix: string,
  count: number,
  pepper: string,
  pepperVersion: number,
  randomValues: RandomValueSource = defaultRandomValueSource,
): Promise<RedemptionCodeMaterial[]> {
  assertCount(count);
  const results: RedemptionCodeMaterial[] = [];
  const hashes = new Set<string>();
  let attempts = 0;

  while (results.length < count) {
    attempts += 1;
    if (attempts > count * 10) throw new Error('Could not generate unique redemption codes.');
    const material = await generateRedemptionCode(prefix, pepper, pepperVersion, randomValues);
    if (hashes.has(material.codeHash)) continue;
    hashes.add(material.codeHash);
    results.push(material);
  }

  return results;
}

export function toRedemptionCodeRecord(
  batchId: string,
  material: RedemptionCodeMaterial,
): RedemptionCodeRecord {
  if (batchId.trim() === '') throw new Error('A redemption batch ID is required.');
  return {
    batchId,
    codeHash: material.codeHash,
    codeHint: material.codeHint,
    pepperVersion: material.pepperVersion,
    status: 'issued',
  };
}

export function redemptionPepperFromEnv(getEnv: (name: string) => string | undefined): {
  readonly pepper: string;
  readonly pepperVersion: number;
} {
  const pepper = getEnv('REDEMPTION_PEPPER');
  const version = Number(getEnv('REDEMPTION_PEPPER_VERSION'));
  if (!pepper || pepper.trim() === '') throw new Error('REDEMPTION_PEPPER is not configured.');
  assertPepperVersion(version);
  return { pepper, pepperVersion: version };
}
