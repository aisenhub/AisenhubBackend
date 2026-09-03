import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const implementationRoots = [
  'apps/account/src',
  'apps/admin/src',
  'packages/auth-client/src',
  'packages/platform-client/src',
  'packages/admin-client/src',
  'packages/contracts/src',
  'supabase/functions',
  'scripts/staging-verification.mjs',
  'playwright.config.ts',
];
const forbiddenPatterns = [
  /platform[_ -]?sessions?/i,
  /\/v1\/session(?:\/exchange)?\b/i,
  /x-csrf-token/i,
  /x-aisenhub-app/i,
  /__Host-aisenhub_session/i,
];
const findings = [];

function filesAt(relativePath) {
  const absolutePath = path.join(repositoryRoot, relativePath);
  if (!fs.existsSync(absolutePath)) return [];
  if (fs.statSync(absolutePath).isFile()) return [absolutePath];
  const files = [];
  for (const entry of fs.readdirSync(absolutePath, { withFileTypes: true })) {
    const child = path.join(absolutePath, entry.name);
    if (entry.isDirectory()) files.push(...filesAt(path.relative(repositoryRoot, child)));
    else if (/\.(?:[cm]?[jt]sx?|mjs|json|sql)$/.test(entry.name)) files.push(child);
  }
  return files;
}

for (const relativeRoot of implementationRoots) {
  for (const filePath of filesAt(relativeRoot)) {
    const contents = fs.readFileSync(filePath, 'utf8');
    for (const pattern of forbiddenPatterns) {
      if (pattern.test(contents))
        findings.push(`${path.relative(repositoryRoot, filePath)} matches ${pattern}`);
    }
  }
}

const migrationDirectory = path.join(repositoryRoot, 'supabase', 'migrations');
const migrationNames = fs
  .readdirSync(migrationDirectory)
  .filter((name) => name.endsWith('.sql'))
  .sort();
if (
  migrationNames.join('\n') !==
  '0001_platform_clean_schema.sql\n0002_platform_security_and_auth.sql'
) {
  findings.push(
    `Expected exactly two clean baseline migrations, found: ${migrationNames.join(', ')}`,
  );
}

if (findings.length > 0) {
  console.error('Architecture regression check failed:');
  for (const finding of findings) console.error(`- ${finding}`);
  process.exitCode = 1;
} else {
  console.log(
    'Architecture regression check passed: implementation paths use bearer context and clean baseline migrations.',
  );
}
