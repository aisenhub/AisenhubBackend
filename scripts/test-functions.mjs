import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const functionsRoot = path.join(repositoryRoot, 'supabase', 'functions');
const functionNames = ['platform-api', 'platform-public', 'platform-admin', 'payment-webhook'];
const codeGenerationSource = path.join(functionsRoot, '_shared', 'redemption-code.ts');

for (const functionName of functionNames) {
  const entrypoint = path.join(functionsRoot, functionName, 'index.ts');
  const source = fs.readFileSync(entrypoint, 'utf8');
  if (!source.includes('Deno.serve(')) {
    throw new Error(`Function ${functionName} does not expose a Deno handler.`);
  }
  if (functionName === 'platform-api') {
    if (!source.includes('../_shared/platform-api.ts')) {
      throw new Error(`Function ${functionName} does not use the platform API router.`);
    }
  } else if (
    functionName === 'platform-public'
      ? !source.includes('../_shared/public-api.ts')
      : !source.includes('../_shared/health.ts')
  ) {
    throw new Error(`Function ${functionName} does not use the shared health handler.`);
  }
}

if (process.argv.includes('code-generation')) {
  const source = fs.readFileSync(codeGenerationSource, 'utf8');
  for (const required of ['crypto.getRandomValues', 'crypto.subtle', 'toRedemptionCodeRecord']) {
    if (!source.includes(required)) {
      throw new Error(`Redemption code generation is missing ${required}.`);
    }
  }
  if (source.includes('console.log') || source.includes('console.error')) {
    throw new Error('Redemption code generation must not log code material.');
  }
  console.log('Redemption code generation security smoke check passed.');
}

console.log(`Function shell smoke check passed for ${functionNames.length} functions.`);
