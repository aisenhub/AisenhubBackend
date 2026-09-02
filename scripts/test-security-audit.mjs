import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const findings = [];

function sourceFiles(directory) {
  if (!fs.existsSync(directory)) return [];
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const filePath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...sourceFiles(filePath));
    else if (/\.(?:[cm]?[jt]sx?|json)$/.test(entry.name)) files.push(filePath);
  }
  return files;
}

function relative(filePath) {
  return path.relative(repositoryRoot, filePath);
}

function checkDirectory(directory, patterns, label) {
  for (const filePath of sourceFiles(directory)) {
    const contents = fs.readFileSync(filePath, 'utf8');
    for (const pattern of patterns) {
      if (pattern.test(contents))
        findings.push(`${label}: ${relative(filePath)} matches ${pattern}`);
    }
  }
}

const adminSource = path.join(repositoryRoot, 'apps', 'admin', 'src');
checkDirectory(
  adminSource,
  [
    /@supabase\//i,
    /supabase-js/i,
    /@aisenhub\/platform-client/i,
    /(?:^|[^a-z])(?:postgres|postgresql|prisma|drizzle-orm)(?:[^a-z]|$)/i,
    /tailwindcss|@tailwind/i,
  ],
  'Admin source bypass/dependency',
);

const adminBundle = path.join(repositoryRoot, 'apps', 'admin', 'dist', 'assets');
const bundleFiles = sourceFiles(adminBundle).filter((filePath) => filePath.endsWith('.js'));
if (bundleFiles.length === 0) findings.push('Admin bundle: no JavaScript assets were built.');
let largestBundle = { bytes: 0, filePath: '' };
for (const filePath of bundleFiles) {
  const bytes = fs.statSync(filePath).size;
  if (bytes > largestBundle.bytes) largestBundle = { bytes, filePath };
  const contents = fs.readFileSync(filePath, 'utf8');
  for (const pattern of [
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
    /\b(?:sb_secret_|sbp_|sk_live_|rk_live_|whsec_)[A-Za-z0-9_-]+/i,
    /SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY|DATABASE_URL|REDEMPTION_PEPPER/i,
    /@supabase\/|supabase-js|postgres(?:ql)?/i,
  ]) {
    if (pattern.test(contents))
      findings.push(`Admin bundle: ${relative(filePath)} matches ${pattern}`);
  }
}
if (largestBundle.bytes > 750_000) {
  findings.push(`Admin bundle: ${relative(largestBundle.filePath)} exceeds 750000 bytes.`);
}

const migrationDirectory = path.join(repositoryRoot, 'supabase', 'migrations');
for (const filePath of sourceFiles(migrationDirectory).filter((filePath) =>
  filePath.endsWith('.sql'),
)) {
  const contents = fs.readFileSync(filePath, 'utf8');
  if (/security\s+definer/i.test(contents) && !/set\s+search_path\s*=/i.test(contents)) {
    findings.push(`Privileged SQL lacks fixed search_path: ${relative(filePath)}`);
  }
  if (/create\s+(?:or\s+replace\s+)?function\s+public\.admin_/i.test(contents)) {
    if (!/revoke\s+all\s+on\s+function/i.test(contents)) {
      findings.push(`Admin SQL function lacks explicit revoke: ${relative(filePath)}`);
    }
    if (!/grant\s+execute\s+on\s+function[\s\S]*?to\s+service_role/i.test(contents)) {
      findings.push(`Admin SQL function lacks service_role grant: ${relative(filePath)}`);
    }
  }
}

if (findings.length > 0) {
  console.error('Security audit failed:');
  for (const finding of findings) console.error(`- ${finding}`);
  process.exitCode = 1;
} else {
  console.log(
    `Security audit passed: ${bundleFiles.length} Admin assets scanned; largest asset ${largestBundle.bytes} bytes; privileged SQL search_path and Admin grants checked.`,
  );
}
