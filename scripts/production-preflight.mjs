import { spawnSync } from 'node:child_process';
import { promises as dns } from 'node:dns';
import process from 'node:process';

const requiredProductionVariables = [
  'PRODUCTION_SUPABASE_PROJECT_REF',
  'PRODUCTION_SUPABASE_URL',
  'PRODUCTION_SUPABASE_ANON_KEY',
  'PRODUCTION_SUPABASE_SERVICE_ROLE_KEY',
  'PRODUCTION_REDEMPTION_PEPPER',
  'PRODUCTION_PAYMENT_WEBHOOK_SECRET',
  'PRODUCTION_API_ORIGIN',
  'PRODUCTION_ACCOUNT_ORIGIN',
  'PRODUCTION_ADMIN_ORIGIN',
];

const canonicalProductionHosts = {
  api: 'api.aisenhub.com',
  account: 'account.aisenhub.com',
  admin: 'admin.aisenhub.com',
};

function present(name) {
  return typeof process.env[name] === 'string' && process.env[name].trim() !== '';
}

function runSupabaseProjectList() {
  const result = spawnSync(
    process.platform === 'win32' ? (process.env.ComSpec ?? 'cmd.exe') : 'pnpm',
    process.platform === 'win32'
      ? ['/d', '/s', '/c', 'pnpm exec supabase projects list --output json']
      : ['exec', 'supabase', 'projects', 'list', '--output', 'json'],
    { cwd: process.cwd(), encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], shell: false },
  );

  if (result.status !== 0) {
    const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
    return {
      status: /access token|supabase login|not logged in/i.test(output)
        ? 'missing_auth'
        : 'unavailable',
      projects: [],
    };
  }

  try {
    const parsed = JSON.parse(result.stdout ?? '[]');
    const projects = Array.isArray(parsed)
      ? parsed
      : Array.isArray(parsed.projects)
        ? parsed.projects
        : [];
    return {
      status: 'available',
      projects: projects.map((project) => ({
        name: typeof project.name === 'string' ? project.name : 'unnamed',
        ref: typeof project.ref === 'string' ? project.ref : null,
        status: typeof project.status === 'string' ? project.status : 'unknown',
        linked: project.linked === true,
      })),
    };
  } catch {
    return { status: 'unavailable', projects: [] };
  }
}

function originState(name) {
  if (!present(name)) return { configured: false, provider: 'not_configured' };
  try {
    const hostname = new URL(process.env[name]).hostname;
    return {
      configured: true,
      provider: hostname.endsWith('.vercel.app') ? 'vercel_provider_url' : 'custom_origin',
    };
  } catch {
    return { configured: true, provider: 'invalid_origin' };
  }
}

function inspectVercelCli() {
  const result = spawnSync('where.exe', ['vercel'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    shell: false,
  });
  return result.status === 0 ? 'available' : 'not_available';
}

function inspectSupabaseIdentity(projectList) {
  if (!present('PRODUCTION_SUPABASE_PROJECT_REF') || !present('PRODUCTION_SUPABASE_URL')) {
    return {
      url: 'not_configured',
      projectVisibility: 'not_configured',
      stagingIsolation: 'not_checked',
    };
  }

  let urlMatchesRef = false;
  try {
    const hostname = new URL(process.env.PRODUCTION_SUPABASE_URL).hostname;
    urlMatchesRef = hostname === `${process.env.PRODUCTION_SUPABASE_PROJECT_REF}.supabase.co`;
  } catch {
    urlMatchesRef = false;
  }

  const projectVisibility =
    projectList.status !== 'available'
      ? 'not_checked'
      : projectList.projects.some(
            (project) => project.ref === process.env.PRODUCTION_SUPABASE_PROJECT_REF,
          )
        ? 'visible'
        : 'not_visible';
  const stagingIsolation = present('STAGING_SUPABASE_PROJECT_REF')
    ? process.env.STAGING_SUPABASE_PROJECT_REF !== process.env.PRODUCTION_SUPABASE_PROJECT_REF
      ? 'isolated'
      : 'collision'
    : 'not_checked';

  return {
    url: urlMatchesRef ? 'matches_project_ref' : 'mismatch',
    projectVisibility,
    stagingIsolation,
  };
}

async function resolveHost(host) {
  try {
    const addresses = await dns.lookup(host, { all: true });
    return { status: addresses.length > 0 ? 'resolved' : 'unresolved' };
  } catch {
    return { status: 'unresolved' };
  }
}

const projectList = runSupabaseProjectList();
const productionRefConfigured = present('PRODUCTION_SUPABASE_PROJECT_REF');
const productionUrlConfigured = present('PRODUCTION_SUPABASE_URL');
const supabaseIdentity = inspectSupabaseIdentity(projectList);
const projectCandidates = projectList.projects.filter(
  (project) =>
    project.name.toLowerCase().includes('production') || project.name === 'aisenhubProject',
);

const dnsState = Object.fromEntries(
  await Promise.all(
    Object.entries(canonicalProductionHosts).map(async ([name, host]) => [
      name,
      await resolveHost(host),
    ]),
  ),
);

const result = {
  mode: process.argv.includes('--check-only') ? 'check-only' : 'default',
  mutation: false,
  supabase: {
    cliAuth: projectList.status,
    visibleProjectCount: projectList.projects.length,
    productionIdentity: {
      projectRefConfigured: productionRefConfigured,
      urlConfigured: productionUrlConfigured,
      candidateProjectCount: projectCandidates.length,
      candidates: projectCandidates.map(({ name, status, linked }) => ({ name, status, linked })),
    },
    environmentIdentity: supabaseIdentity,
  },
  variables: Object.fromEntries(requiredProductionVariables.map((name) => [name, present(name)])),
  origins: {
    api: originState('PRODUCTION_API_ORIGIN'),
    account: originState('PRODUCTION_ACCOUNT_ORIGIN'),
    admin: originState('PRODUCTION_ADMIN_ORIGIN'),
  },
  hosting: {
    vercelCli: inspectVercelCli(),
  },
  canonicalDns: dnsState,
};

const missingVariables = requiredProductionVariables.filter((name) => !result.variables[name]);
const productionReady =
  result.supabase.cliAuth === 'available' &&
  productionRefConfigured &&
  productionUrlConfigured &&
  supabaseIdentity.url === 'matches_project_ref' &&
  supabaseIdentity.projectVisibility === 'visible' &&
  supabaseIdentity.stagingIsolation !== 'collision' &&
  missingVariables.length === 0 &&
  Object.values(result.origins).every(
    (origin) => origin.configured && origin.provider !== 'invalid_origin',
  );

result.readiness = productionReady ? 'ready_for_next_gate' : 'human_gate_required';
result.humanGate = productionReady ? 'HG-003 can be skipped' : 'HG-003 ready';
result.missingVariableCount = missingVariables.length;

console.log(JSON.stringify(result, null, 2));
