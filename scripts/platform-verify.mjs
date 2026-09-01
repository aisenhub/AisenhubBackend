import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import process from 'node:process';

const repositoryRoot = process.cwd();
const generatedTypesPath = join(repositoryRoot, 'supabase', 'types', 'database.ts');
const isWindows = process.platform === 'win32';

function quoteWindowsArgument(argument) {
  if (/^[\w@%+=:,./-]+$/.test(argument)) return argument;
  return `"${argument.replaceAll('"', '\\"')}"`;
}

function runPnpm(args, { capture = false } = {}) {
  const options = {
    cwd: repositoryRoot,
    encoding: 'utf8',
    stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit',
  };

  if (isWindows) {
    const commandLine = ['pnpm', ...args].map(quoteWindowsArgument).join(' ');
    return spawnSync(process.env.ComSpec ?? 'cmd.exe', ['/d', '/s', '/c', commandLine], options);
  }

  return spawnSync('pnpm', args, options);
}

function assertSuccessful(result, label) {
  if (result.error) throw new Error(`${label} could not start: ${result.error.message}`);
  if (result.status !== 0)
    throw new Error(`${label} failed with exit code ${result.status ?? 'unknown'}.`);
}

function runStep(label, args) {
  console.log(`\n[platform:verify] START ${label}`);
  const result = runPnpm(args);
  assertSuccessful(result, label);
  console.log(`[platform:verify] PASS ${label}`);
}

function sha256(filePath) {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}

function wait(milliseconds) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
}

function localSupabaseStatus() {
  const result = runPnpm(['exec', 'supabase', 'status', '--output', 'json'], { capture: true });
  if (result.error)
    throw new Error(`Supabase Local status could not start: ${result.error.message}`);
  return result.status === 0;
}

function waitForLocalSupabase(attempts = 10) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (localSupabaseStatus()) return true;
    if (attempt < attempts - 1) wait(2000);
  }
  return false;
}

function ensureLocalSupabase() {
  console.log('[platform:verify] Checking Supabase Local readiness.');
  if (localSupabaseStatus()) {
    console.log('[platform:verify] Supabase Local is already running.');
    return;
  }

  console.log('[platform:verify] Supabase Local is not running; starting it now.');
  const start = runPnpm(['exec', 'supabase', 'start'], { capture: true });
  if (start.error) throw new Error(`Supabase Local start could not start: ${start.error.message}`);
  if (start.status !== 0 && !waitForLocalSupabase()) {
    throw new Error(`Supabase Local start failed with exit code ${start.status ?? 'unknown'}.`);
  }
  if (!waitForLocalSupabase()) {
    throw new Error('Supabase Local did not become ready after startup.');
  }
  console.log('[platform:verify] Supabase Local is ready.');
}

function verifyGeneratedTypeStability() {
  const firstHash = sha256(generatedTypesPath);
  runStep('Repeat Supabase type generation', ['supabase:typegen']);
  const secondHash = sha256(generatedTypesPath);
  if (firstHash !== secondHash) {
    throw new Error('Supabase generated types changed between consecutive generations.');
  }
  console.log('[platform:verify] PASS generated type stability');
}

try {
  ensureLocalSupabase();
  runStep('Local database reset and seed', ['db:reset']);
  runStep('Supabase type generation', ['supabase:typegen']);
  verifyGeneratedTypeStability();
  runStep('Database tests', ['db:test']);
  runStep('RLS tests', ['rls:test']);
  runStep('Local Auth fixture verification', ['fixtures:verify']);
  runStep('Edge Function shell tests', ['functions:test']);
  runStep('Unit tests', ['test']);
  runStep('Contract tests', ['test:contract']);
  runStep('Integration tests', ['test:integration']);
  runStep('Typecheck', ['typecheck']);
  runStep('Lint', ['lint']);
  runStep('Format check', ['format:check']);
  runStep('Workspace build', ['build']);
  runStep('Playwright E2E discovery', ['test:e2e', '--', '--list']);
  runStep('Boundary check', ['boundaries:check']);
  runStep('Failure-propagation harness', ['test:harness:negative']);
  console.log('\n[platform:verify] COMPLETE all Local checks passed.');
} catch (error) {
  console.error(`\n[platform:verify] FAILED: ${error.message}`);
  process.exitCode = 1;
}
