import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomUUID } from 'node:crypto';

const execFileAsync = promisify(execFile);
const databaseContainer = 'supabase_db_aisenhub-platform-local';
const ownerId = randomUUID();
const otherId = randomUUID();
const productId = randomUUID();
const versionId = randomUUID();
const batchId = randomUUID();
const codeId = randomUUID();
const productSku = `REDEEM_CONCURRENCY_${Date.now()}`;
const ownerEmail = `redemption-concurrency-owner-${Date.now()}@aisenhub.test`;
const otherEmail = `redemption-concurrency-other-${Date.now()}@aisenhub.test`;
const codeHash = '9'.repeat(64);

async function sql(statement) {
  return execFileAsync(
    'docker.exe',
    [
      'exec',
      databaseContainer,
      'psql',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-v',
      'ON_ERROR_STOP=1',
      '-At',
      '-c',
      statement,
    ],
    { maxBuffer: 4 * 1024 * 1024 },
  );
}

function quote(value) {
  return `'${value.replaceAll("'", "''")}'`;
}

const setup = `
insert into auth.users
  (id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous)
values
  (${quote(ownerId)}, 'authenticated', 'authenticated', ${quote(ownerEmail)}, 'not-used-by-this-test', now(),
   '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false),
  (${quote(otherId)}, 'authenticated', 'authenticated', ${quote(otherEmail)}, 'not-used-by-this-test', now(),
   '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now(), false);
insert into platform.products (id, sku, name, billing_type)
values (${quote(productId)}, ${quote(productSku)}, 'Redemption Concurrency Product', 'one_time');
insert into platform.product_versions
  (id, product_id, version, status, published_at, sales_terms)
values (${quote(versionId)}, ${quote(productId)}, 1, 'published', now(), '{}'::jsonb);
insert into platform.redemption_batches
  (id, name, product_id, product_version_id, code_prefix, quantity, per_user_limit, status, source, created_by)
values (${quote(batchId)}, 'Concurrency Batch', ${quote(productId)}, ${quote(versionId)}, 'AH-CONCURRENCY', 1, 1, 'active', 'test', ${quote(ownerId)});
insert into platform.redemption_codes
  (id, batch_id, code_hash, code_hint, pepper_version)
values (${quote(codeId)}, ${quote(batchId)}, ${quote(codeHash)}, 'AH-CONCURRENCY-****-9999', 1);
`;

const firstClaim = `
begin;
select id from platform.redemption_codes where id = ${quote(codeId)} for update;
set local role service_role;
select pg_sleep(1);
select * from public.redeem_code(${quote(codeHash)}, ${quote(ownerId)}, 'concurrency-owner', 'concurrency-owner-payload');
commit;
`;
const secondClaim = `
begin;
set local role service_role;
select * from public.redeem_code(${quote(codeHash)}, ${quote(otherId)}, 'concurrency-other', 'concurrency-other-payload');
commit;
`;

await sql(setup);
const first = sql(firstClaim);
await new Promise((resolve) => setTimeout(resolve, 250));
let secondSucceeded = false;
try {
  await sql(secondClaim);
  secondSucceeded = true;
} catch {
  // The losing claim must fail with the generic unavailable-code error.
}
await first;

if (secondSucceeded) {
  throw new Error('Concurrent redemption unexpectedly allowed two claims.');
}

const verification = await sql(`
select
  (select count(*) from platform.redemptions where code_id = ${quote(codeId)}) || '|' ||
  (select status from platform.redemption_codes where id = ${quote(codeId)}) || '|' ||
  (select count(*) from platform.entitlement_grants where product_id = ${quote(productId)}) || '|' ||
  (select count(*) from platform.audit_logs where action = 'redemptions.redeem' and target_type = 'redemption')
`);
const result = verification.stdout.trim();
if (result !== '1|redeemed|1|1') {
  throw new Error(`Concurrent redemption verification failed: ${result}`);
}

await sql(`
begin;
set local session_replication_role = replica;
delete from platform.audit_logs where target_type = 'redemption' and target_id in (select id from platform.redemptions where code_id = ${quote(codeId)});
delete from platform.redemptions where code_id = ${quote(codeId)};
delete from platform.audit_logs where action = 'entitlements.grant' and target_type = 'entitlement_grant' and target_id in (select id from platform.entitlement_grants where product_id = ${quote(productId)});
delete from platform.entitlement_grants where product_id = ${quote(productId)};
delete from platform.idempotency_records where actor_key in (${quote(`user:${ownerId}`)}, ${quote(`user:${otherId}`)});
delete from platform.redemption_codes where id = ${quote(codeId)};
delete from platform.redemption_batches where id = ${quote(batchId)};
delete from platform.product_versions where id = ${quote(versionId)};
delete from platform.products where id = ${quote(productId)};
delete from platform.profiles where id in (${quote(ownerId)}, ${quote(otherId)});
delete from auth.users where id in (${quote(ownerId)}, ${quote(otherId)});
commit;
`);

console.log('Redemption concurrency check passed: exactly one of two concurrent claims succeeded.');
