import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const scanRoot = process.argv.includes('--root')
  ? path.resolve(process.argv[process.argv.indexOf('--root') + 1])
  : repositoryRoot;

const workspaceRoots = ['apps', 'packages'];
const forbiddenAdminUiDependencies = [
  '@chakra-ui/',
  '@mui/',
  '@mantine/',
  '@radix-ui/',
  'arco-design',
  'chakra-ui',
  'element-plus',
  'material-ui',
  'prime-react',
  'shadcn',
];
const forbiddenAdminClientPatterns = [
  '@supabase/',
  'supabase',
  'pg',
  'postgres',
  'postgresql',
  'prisma',
  'drizzle-orm',
];
const forbiddenAdminSourcePatterns = [
  ...forbiddenAdminUiDependencies,
  '@supabase/',
  'supabase-js',
  'postgres',
  'postgresql',
  'prisma',
  'drizzle-orm',
  'tailwindcss',
  '@tailwind',
];

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function workspaceManifests(root) {
  const manifests = [];
  for (const workspaceRoot of workspaceRoots) {
    const absoluteRoot = path.join(root, workspaceRoot);
    if (!fs.existsSync(absoluteRoot)) continue;
    for (const entry of fs.readdirSync(absoluteRoot, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const manifestPath = path.join(absoluteRoot, entry.name, 'package.json');
      if (fs.existsSync(manifestPath)) manifests.push(manifestPath);
    }
  }
  return manifests;
}

function allDependencies(manifest) {
  return Object.keys({
    ...manifest.dependencies,
    ...manifest.devDependencies,
    ...manifest.peerDependencies,
  });
}

function sourceFiles(directory) {
  if (!fs.existsSync(directory)) return [];
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...sourceFiles(entryPath));
    else if (/\.(?:[cm]?[jt]sx?|vue)$/.test(entry.name)) files.push(entryPath);
  }
  return files;
}

function fail(message) {
  console.error(`Boundary violation: ${message}`);
  process.exitCode = 1;
}

const manifests = workspaceManifests(scanRoot);
const workspaceByName = new Map();
for (const manifestPath of manifests) {
  const manifest = readJson(manifestPath);
  workspaceByName.set(manifest.name, { manifest, manifestPath });
}

const graph = new Map();
for (const [name, entry] of workspaceByName) {
  const dependencies = allDependencies(entry.manifest).filter((dependency) =>
    workspaceByName.has(dependency),
  );
  graph.set(name, dependencies);
}

function visit(name, active, visited) {
  if (active.has(name)) {
    fail(`circular workspace dependency involving ${name}`);
    return;
  }
  if (visited.has(name)) return;
  active.add(name);
  for (const dependency of graph.get(name) ?? []) visit(dependency, active, visited);
  active.delete(name);
  visited.add(name);
}

const visited = new Set();
for (const name of graph.keys()) visit(name, new Set(), visited);

const adminClient = workspaceByName.get('@aisenhub/admin-client');
if (adminClient) {
  if (allDependencies(adminClient.manifest).includes('@aisenhub/platform-client')) {
    fail('admin-client must not depend on platform-client');
  }
  for (const dependency of allDependencies(adminClient.manifest)) {
    if (
      forbiddenAdminClientPatterns.some((pattern) => dependency.toLowerCase().includes(pattern))
    ) {
      fail(`admin-client must not depend on database or Supabase package ${dependency}`);
    }
  }
  const sourceDirectory = path.dirname(adminClient.manifestPath);
  for (const filePath of sourceFiles(sourceDirectory)) {
    const contents = fs.readFileSync(filePath, 'utf8');
    for (const pattern of forbiddenAdminClientPatterns) {
      if (contents.toLowerCase().includes(pattern.toLowerCase())) {
        fail(
          `admin-client source ${path.relative(scanRoot, filePath)} contains forbidden reference ${pattern}`,
        );
      }
    }
  }
}

const admin = workspaceByName.get('@aisenhub/admin');
if (admin) {
  for (const dependency of allDependencies(admin.manifest)) {
    if (
      forbiddenAdminUiDependencies.some((pattern) => dependency.toLowerCase().includes(pattern))
    ) {
      fail(`Admin must use Ant Design as its sole primary component system; found ${dependency}`);
    }
  }
  const adminAgents = path.join(path.dirname(admin.manifestPath), 'AGENTS.md');
  if (!fs.existsSync(adminAgents)) fail('apps/admin/AGENTS.md is missing');

  for (const filePath of sourceFiles(path.dirname(admin.manifestPath))) {
    const contents = fs.readFileSync(filePath, 'utf8').toLowerCase();
    for (const pattern of forbiddenAdminSourcePatterns) {
      if (contents.includes(pattern.toLowerCase())) {
        fail(
          `Admin source ${path.relative(scanRoot, filePath)} contains forbidden reference ${pattern}`,
        );
      }
    }
  }
}

if (admin) {
  for (const filePath of sourceFiles(path.dirname(admin.manifestPath))) {
    const contents = fs.readFileSync(filePath, 'utf8');
    if (contents.includes('@aisenhub/platform-client')) {
      fail(
        `Admin source ${path.relative(scanRoot, filePath)} must use admin-client, not platform-client`,
      );
    }
  }
}

if (process.exitCode !== 1)
  console.log(`Boundary check passed for ${manifests.length} workspace manifests.`);
