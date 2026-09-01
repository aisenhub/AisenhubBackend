import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const functionsRoot = path.join(repositoryRoot, 'supabase', 'functions');
const functionNames = ['platform-api', 'platform-public', 'platform-admin', 'payment-webhook'];

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
  } else if (!source.includes('../_shared/health.ts')) {
    throw new Error(`Function ${functionName} does not use the shared health handler.`);
  }
}

console.log(`Function shell smoke check passed for ${functionNames.length} functions.`);
