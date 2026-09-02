import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import process from 'node:process';

const repositoryRoot = resolve(import.meta.dirname, '..');
const environment = readOption('--env');
const offline = process.argv.includes('--offline');
const outputRoot = join(
  repositoryRoot,
  'supabase',
  '.temp',
  'release-bundle',
  environment ?? 'unknown',
);
const migrationsRoot = join(repositoryRoot, 'supabase', 'migrations');
const functionsRoot = join(repositoryRoot, 'supabase', 'functions');

if (environment !== 'staging') {
  console.error('Usage: pnpm release:bundle --env staging [--offline]');
  process.exit(1);
}

function readOption(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function sha256(filePath) {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}

function listFiles(root, { include = () => true } = {}) {
  const files = [];
  function visit(current) {
    for (const entry of readdirSync(current, { withFileTypes: true }).sort((a, b) =>
      a.name.localeCompare(b.name),
    )) {
      const absolutePath = join(current, entry.name);
      if (entry.isDirectory()) visit(absolutePath);
      else if (include(absolutePath)) files.push(absolutePath);
    }
  }
  visit(root);
  return files;
}

function artifactFiles(root) {
  return listFiles(root, { include: (filePath) => !filePath.endsWith('.map') });
}

function toArtifactEntries(root, files) {
  return files.map((filePath) => ({
    path: relative(repositoryRoot, filePath).replaceAll('\\', '/'),
    sha256: sha256(filePath),
    bytes: statSync(filePath).size,
  }));
}

function runPnpm(args) {
  const safeEnvironment = { ...process.env };
  for (const name of Object.keys(safeEnvironment)) {
    if (
      /^(?:SUPABASE_ACCESS_TOKEN|STAGING_.*(?:SECRET|PEPPER|KEY)|.*(?:PASSWORD|PRIVATE_KEY|SERVICE_ROLE))/i.test(
        name,
      )
    ) {
      delete safeEnvironment[name];
    }
  }
  const commandLine = ['pnpm', ...args]
    .map((argument) =>
      /^[\w@%+=:,./-]+$/.test(argument) ? argument : `"${argument.replaceAll('"', '\\"')}"`,
    )
    .join(' ');
  const result = spawnSync(
    process.platform === 'win32' ? (process.env.ComSpec ?? 'cmd.exe') : 'pnpm',
    process.platform === 'win32' ? ['/d', '/s', '/c', commandLine] : args,
    { cwd: repositoryRoot, env: safeEnvironment, encoding: 'utf8', stdio: 'inherit' },
  );
  if (result.error)
    throw new Error(`pnpm ${args.join(' ')} could not start: ${result.error.message}`);
  if (result.status !== 0)
    throw new Error(`pnpm ${args.join(' ')} failed with exit code ${result.status ?? 'unknown'}.`);
}

function gitOutput(args) {
  return execFileSync('git', args, { cwd: repositoryRoot, encoding: 'utf8' }).trim();
}

function validateMigrations() {
  const files = readdirSync(migrationsRoot)
    .filter((name) => name.endsWith('.sql'))
    .sort((a, b) => a.localeCompare(b));
  if (files.length === 0) throw new Error('No SQL migrations were found.');
  const duplicateNames = files.filter((name, index) => files.indexOf(name) !== index);
  if (duplicateNames.length > 0)
    throw new Error(`Duplicate migration names found: ${duplicateNames.join(', ')}`);
  const invalidNames = files.filter((name) => !/^\d{4,}_.*\.sql$/.test(name));
  if (invalidNames.length > 0)
    throw new Error(
      `Migration names are not ordered timestamp prefixes: ${invalidNames.join(', ')}`,
    );
  return files.map((name) => ({
    path: `supabase/migrations/${name}`,
    sha256: sha256(join(migrationsRoot, name)),
    bytes: statSync(join(migrationsRoot, name)).size,
  }));
}

function assertNoSecretText(files) {
  const patterns = [
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
    /\b(?:sbp|sb_secret)_[A-Za-z0-9_-]{8,}\b/,
    /\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{12,}\b/,
    /\bwhsec_[A-Za-z0-9]{12,}\b/,
  ];
  for (const filePath of files) {
    const contents = readFileSync(filePath);
    if (contents.includes(0)) continue;
    if (patterns.some((pattern) => pattern.test(contents.toString('utf8')))) {
      throw new Error(
        `Potential secret material detected in release artifact ${relative(repositoryRoot, filePath)}.`,
      );
    }
  }
}

try {
  const gitSha = gitOutput(['rev-parse', 'HEAD']);
  const gitCommitTimestamp = gitOutput(['show', '-s', '--format=%cI', 'HEAD']);
  const migrationEntries = validateMigrations();

  console.log(`[release:bundle] Building staging application artifacts from ${gitSha}.`);
  runPnpm(['build']);

  const appEntries = [];
  for (const appName of ['account', 'admin']) {
    const appRoot = join(repositoryRoot, 'apps', appName, 'dist');
    const files = artifactFiles(appRoot);
    if (files.length === 0) throw new Error(`Build output is empty: apps/${appName}/dist`);
    assertNoSecretText(files);
    appEntries.push({ name: appName, files: toArtifactEntries(appRoot, files) });
  }

  const functionFiles = artifactFiles(functionsRoot).filter(
    (filePath) => !filePath.endsWith(`${'functions'}\\.env`),
  );
  if (functionFiles.length === 0) throw new Error('Edge Function source output is empty.');
  assertNoSecretText(functionFiles);
  const functionEntries = toArtifactEntries(functionsRoot, functionFiles);

  if (!offline) runPnpm(['staging:preflight', '--check-only']);
  mkdirSync(outputRoot, { recursive: true });
  const manifest = {
    schemaVersion: 1,
    environment,
    gitSha,
    sourceDate: gitCommitTimestamp,
    reproducibility: {
      source: 'git',
      migrationOrdering: 'lexicographic filename order',
      localSecretsIncluded: false,
    },
    migrations: migrationEntries,
    edgeFunctions: functionEntries,
    applications: appEntries,
    requiredVariables: [
      'STAGING_SUPABASE_PROJECT_REF',
      'STAGING_SUPABASE_URL',
      'STAGING_SUPABASE_ANON_KEY',
      'STAGING_SUPABASE_SERVICE_ROLE_KEY',
      'STAGING_REDEMPTION_PEPPER',
      'STAGING_PAYMENT_WEBHOOK_SECRET',
      'STAGING_API_ORIGIN',
      'STAGING_ACCOUNT_ORIGIN',
      'STAGING_ADMIN_ORIGIN',
    ],
    dnsAndCorsChecklist: [
      'api.aisenhub.com or approved Staging API origin',
      'account.aisenhub.com or approved Staging Account origin',
      'admin.aisenhub.com or approved Staging Admin origin',
      'CORS allowlist contains only approved Staging application origins',
      'Production database, secrets, webhooks, and DNS remain isolated',
    ],
    recovery: {
      stop: [
        'migration failure',
        'checksum mismatch',
        'secret scan finding',
        'origin/CORS mismatch',
        'health or smoke failure',
      ],
      retry:
        'Re-run the same Git SHA after correcting the failed prerequisite; do not edit or reorder applied migrations.',
      rollback:
        'Restore the previous verified artifact and use a forward migration for schema correction; never reset Staging as a rollback.',
    },
  };
  const manifestPath = join(outputRoot, 'manifest.json');
  const checksumsPath = join(outputRoot, 'checksums.sha256');
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  const checksumLines = [
    `${sha256(manifestPath)}  manifest.json`,
    ...migrationEntries.map((entry) => `${entry.sha256}  ${entry.path}`),
    ...functionEntries.map((entry) => `${entry.sha256}  ${entry.path}`),
    ...appEntries.flatMap((app) => app.files.map((entry) => `${entry.sha256}  ${entry.path}`)),
  ];
  writeFileSync(checksumsPath, `${checksumLines.join('\n')}\n`);
  console.log(`[release:bundle] PASS ${relative(repositoryRoot, manifestPath)}`);
  console.log(`[release:bundle] PASS ${relative(repositoryRoot, checksumsPath)}`);
  console.log(
    `[release:bundle] Git SHA ${gitSha}; migrations ${migrationEntries.length}; functions ${functionEntries.length}; applications 2.`,
  );
} catch (error) {
  console.error(`[release:bundle] FAILED: ${error.message}`);
  process.exitCode = 1;
}
