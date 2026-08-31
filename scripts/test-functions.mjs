import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const functionsRoot = path.join(repositoryRoot, 'supabase', 'functions');
const functionNames = ['platform-api', 'platform-public', 'platform-admin', 'payment-webhook'];

for (const functionName of functionNames) {
  const entrypoint = path.join(functionsRoot, functionName, 'index.ts');
  const source = fs.readFileSync(entrypoint, 'utf8');
  if (!source.includes("Deno.serve(() => healthResponse('")) {
    throw new Error(`Function ${functionName} does not expose the required health handler.`);
  }
  if (!source.includes('../_shared/health.ts')) {
    throw new Error(`Function ${functionName} does not use the shared health handler.`);
  }
}

console.log(`Function shell smoke check passed for ${functionNames.length} functions.`);
