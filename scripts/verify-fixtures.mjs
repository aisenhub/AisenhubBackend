import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import process from 'node:process';

const repositoryRoot = process.cwd();

const fixtureFile = new URL('../tests/fixtures/local-fixtures.json', import.meta.url);
const fixtures = JSON.parse(readFileSync(fixtureFile, 'utf8'));

if (fixtures.environment !== 'local-only') {
  throw new Error('Fixture manifest is not marked local-only.');
}

const supabaseCli =
  process.platform === 'win32'
    ? join(process.cwd(), 'node_modules', '.bin', 'supabase.cmd')
    : join(process.cwd(), 'node_modules', '.bin', 'supabase');
const status =
  process.platform === 'win32'
    ? spawnSync(
        process.env.ComSpec ?? 'cmd.exe',
        ['/d', '/s', '/c', `${supabaseCli} status --output env`],
        {
          encoding: 'utf8',
          shell: false,
        },
      )
    : spawnSync(supabaseCli, ['status', '--output', 'env'], {
        encoding: 'utf8',
        shell: false,
      });

if (status.status !== 0) {
  throw new Error('Supabase Local is not running; start it before verifying fixtures.');
}

const localEnv = Object.fromEntries(
  status.stdout
    .split(/\r?\n/)
    .map((line) => line.match(/^([A-Z0-9_]+)=(.*)$/))
    .filter(Boolean)
    .map(([, key, value]) => [key, value.replace(/^"|"$/g, '')]),
);

const apiUrl = localEnv.API_URL;
const anonKey = localEnv.ANON_KEY;
const serviceRoleKey = localEnv.SERVICE_ROLE_KEY;

if (!apiUrl?.startsWith('http://127.0.0.1:') || !anonKey || !serviceRoleKey) {
  throw new Error('Fixture verification requires the local loopback API and local anon key.');
}

const adminHeaders = {
  apikey: serviceRoleKey,
  authorization: `Bearer ${serviceRoleKey}`,
  'content-type': 'application/json',
};

const usersResponse = await fetch(`${apiUrl}/auth/v1/admin/users?page=1&per_page=100`, {
  headers: adminHeaders,
});

if (!usersResponse.ok) {
  throw new Error(`Local Auth fixture listing failed (HTTP ${usersResponse.status}).`);
}

const usersBody = await usersResponse.json();
const existingUsers = usersBody.users ?? [];

for (const fixture of fixtures.users) {
  const existingUser = existingUsers.find(
    (user) => user.id === fixture.id || user.email === fixture.email,
  );

  if (existingUser && (existingUser.id !== fixture.id || existingUser.email !== fixture.email)) {
    throw new Error(`A Local Auth user conflicts with the ${fixture.role} fixture.`);
  }

  if (!existingUser) {
    const createResponse = await fetch(`${apiUrl}/auth/v1/admin/users`, {
      method: 'POST',
      headers: adminHeaders,
      body: JSON.stringify({
        id: fixture.id,
        email: fixture.email,
        email_confirm: true,
        password: fixture.password,
        user_metadata: {
          fixture_role: fixture.role,
          environment: 'local-only',
        },
      }),
    });

    if (!createResponse.ok) {
      throw new Error(
        `Local Auth could not create the ${fixture.role} fixture (HTTP ${createResponse.status}).`,
      );
    }
  } else {
    const updateResponse = await fetch(`${apiUrl}/auth/v1/admin/users/${fixture.id}`, {
      method: 'PUT',
      headers: adminHeaders,
      body: JSON.stringify({
        email: fixture.email,
        email_confirm: true,
        password: fixture.password,
        user_metadata: {
          fixture_role: fixture.role,
          environment: 'local-only',
        },
      }),
    });

    if (!updateResponse.ok) {
      throw new Error(
        `Local Auth could not prepare the ${fixture.role} fixture (HTTP ${updateResponse.status}).`,
      );
    }
  }

  const response = await fetch(`${apiUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: {
      apikey: anonKey,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      email: fixture.email,
      password: fixture.password,
    }),
  });

  if (!response.ok) {
    const errorBody = await response.json().catch(() => ({}));
    const reason = errorBody.error_code ?? errorBody.msg ?? errorBody.error ?? 'unknown error';
    throw new Error(
      `Local Auth rejected the ${fixture.role} fixture (HTTP ${response.status}: ${reason}).`,
    );
  }

  const body = await response.json();
  if (body.user?.id !== fixture.id || body.user?.email !== fixture.email) {
    throw new Error(`The ${fixture.role} fixture returned an unexpected identity.`);
  }
}

const localAdminSeedFile = join(repositoryRoot, 'scripts', 'seed-local-admin-memberships.sql');
const adminSeed =
  process.platform === 'win32'
    ? spawnSync(
        process.env.ComSpec ?? 'cmd.exe',
        ['/d', '/s', '/c', `${supabaseCli} db query --local --file ${localAdminSeedFile}`],
        { cwd: repositoryRoot, encoding: 'utf8', shell: false },
      )
    : spawnSync(supabaseCli, ['db', 'query', '--local', '--file', localAdminSeedFile], {
        cwd: repositoryRoot,
        encoding: 'utf8',
        shell: false,
      });

if (adminSeed.status !== 0) {
  throw new Error('Local Admin fixture membership seeding failed.');
}

const localCatalogSeedFile = join(repositoryRoot, 'scripts', 'seed-local-catalog-fixtures.sql');
const catalogSeed =
  process.platform === 'win32'
    ? spawnSync(
        process.env.ComSpec ?? 'cmd.exe',
        ['/d', '/s', '/c', `${supabaseCli} db query --local --file ${localCatalogSeedFile}`],
        { cwd: repositoryRoot, encoding: 'utf8', shell: false },
      )
    : spawnSync(supabaseCli, ['db', 'query', '--local', '--file', localCatalogSeedFile], {
        cwd: repositoryRoot,
        encoding: 'utf8',
        shell: false,
      });

if (catalogSeed.status !== 0) {
  throw new Error('Local Catalog/Entitlement/Redemption fixture seeding failed.');
}

console.log(
  `Verified ${fixtures.users.length} deterministic Local Auth fixtures and Local P2 domain fixtures.`,
);
