-- Explicit Admin redemption batch commands. Plaintext code material is never
-- accepted by this function; only HMAC digests and safe hints cross the DB boundary.

create or replace function public.admin_redemption_command(
  p_actor_id uuid,
  p_action text,
  p_resource_id uuid default null,
  p_payload jsonb default '{}'::jsonb,
  p_reason text default null,
  p_idempotency_key text default null,
  p_request_hash text default null,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  idempotency_row platform.idempotency_records%rowtype;
  batch_row platform.redemption_batches%rowtype;
  version_row platform.product_versions%rowtype;
  product_row platform.products%rowtype;
  code_record jsonb;
  target_id uuid;
  target_type text := 'redemption_batch';
  before_summary jsonb := '{}'::jsonb;
  after_summary jsonb;
  result jsonb;
  audit_id_value uuid;
  requested_quantity integer;
  command_status text;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'Redemption commands require an active Admin member';
  end if;
  if p_action not in ('create_redemption_batch', 'generate_redemption_codes',
                      'pause_redemption_batch', 'close_redemption_batch') then
    raise exception using errcode = '22023', message = 'The Redemption command is not supported';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'The Redemption command payload is invalid';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A Redemption command reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.redemption.command', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.redemption.command'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body;
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The Redemption command is already in progress';
    end if;
  end if;

  if p_action = 'create_redemption_batch' then
    if p_resource_id is not null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in
         ('name', 'productId', 'productVersionId', 'codePrefix', 'quantity', 'perUserLimit', 'startsAt', 'expiresAt', 'source'))
       or p_payload->>'name' is null or btrim(p_payload->>'name') = ''
       or p_payload->>'productId' is null or p_payload->>'productVersionId' is null
       or p_payload->>'codePrefix' !~ '^[A-Z0-9]+(?:-[A-Z0-9]+)*$'
       or p_payload->>'quantity' is null or p_payload->>'source' is null or btrim(p_payload->>'source') = '' then
      raise exception using errcode = '22023', message = 'The Redemption batch fields are invalid';
    end if;
    select product.*
      into product_row
      from platform.products as product
     where product.id = (p_payload->>'productId')::uuid
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product or Product Version was not found';
    end if;
    select version.*
      into version_row
      from platform.product_versions as version
     where version.id = (p_payload->>'productVersionId')::uuid
       and version.product_id = product_row.id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product or Product Version was not found';
    end if;
    if version_row.status <> 'published' then
      raise exception using errcode = '23514', message = 'Redemption batches require a published Product Version';
    end if;
    insert into platform.redemption_batches
      (name, product_id, product_version_id, code_prefix, quantity, per_user_limit,
       starts_at, expires_at, source, created_by)
    values
      (btrim(p_payload->>'name'), product_row.id, version_row.id, p_payload->>'codePrefix',
       (p_payload->>'quantity')::integer,
       coalesce((p_payload->>'perUserLimit')::integer, 1),
       coalesce((p_payload->>'startsAt')::timestamptz, timezone('utc', now())),
       case when p_payload ? 'expiresAt' then (p_payload->>'expiresAt')::timestamptz else null end,
       btrim(p_payload->>'source'), p_actor_id)
    returning * into batch_row;
    target_id := batch_row.id;
    result := jsonb_build_object(
      'id', batch_row.id, 'name', batch_row.name, 'productSku', product_row.sku,
      'productVersion', version_row.version, 'status', batch_row.status,
      'codePrefix', batch_row.code_prefix, 'quantity', batch_row.quantity,
      'issuedCount', 0, 'redeemedCount', 0, 'startsAt', batch_row.starts_at,
      'expiresAt', batch_row.expires_at, 'createdAt', batch_row.created_at
    );
    after_summary := jsonb_build_object('id', batch_row.id, 'status', batch_row.status,
      'productId', batch_row.product_id, 'productVersionId', batch_row.product_version_id,
      'quantity', batch_row.quantity);
  elsif p_action = 'generate_redemption_codes' then
    if p_resource_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('quantity', 'codeRecords'))
       or p_payload->>'quantity' is null
       or jsonb_typeof(p_payload->'codeRecords') <> 'array' then
      raise exception using errcode = '22023', message = 'The Redemption code generation fields are invalid';
    end if;
    requested_quantity := (p_payload->>'quantity')::integer;
    if requested_quantity < 1 or requested_quantity > 10000
       or jsonb_array_length(p_payload->'codeRecords') <> requested_quantity then
      raise exception using errcode = '22023', message = 'The Redemption code generation quantity is invalid';
    end if;
    select batch.*
      into batch_row
      from platform.redemption_batches as batch
     where batch.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Redemption batch was not found';
    end if;
    if batch_row.status <> 'draft' then
      raise exception using errcode = '23514', message = 'Codes can only be generated for a draft batch';
    end if;
    select version.*
      into version_row
      from platform.product_versions as version
     where version.id = batch_row.product_version_id
       and version.product_id = batch_row.product_id
     for update;
    if not found or version_row.status <> 'published' then
      raise exception using errcode = '23514', message = 'Codes require a published Product Version';
    end if;
    if requested_quantity <> batch_row.quantity then
      raise exception using errcode = '22023', message = 'Generation quantity must match the batch quantity';
    end if;
    if exists (select 1 from platform.redemption_codes where batch_id = batch_row.id) then
      raise exception using errcode = '23514', message = 'Redemption codes have already been generated for this batch';
    end if;
    for code_record in select value from jsonb_array_elements(p_payload->'codeRecords') as values(value) loop
      if exists (select 1 from jsonb_object_keys(code_record) as key where key not in ('codeHash', 'codeHint', 'pepperVersion'))
         or code_record->>'codeHash' !~ '^[0-9a-f]{64}$'
         or btrim(coalesce(code_record->>'codeHint', '')) = ''
         or (code_record->>'pepperVersion')::integer < 1 then
        raise exception using errcode = '22023', message = 'A generated Redemption code record is invalid';
      end if;
    end loop;
    insert into platform.redemption_codes (batch_id, code_hash, code_hint, pepper_version)
    select batch_row.id, value->>'codeHash', value->>'codeHint', (value->>'pepperVersion')::smallint
      from jsonb_array_elements(p_payload->'codeRecords') as values(value);
    update platform.redemption_batches set status = 'active' where id = batch_row.id;
    select batch.* into batch_row from platform.redemption_batches as batch where batch.id = p_resource_id;
    target_id := batch_row.id;
    result := jsonb_build_object(
      'batchId', batch_row.id,
      'codes', (select jsonb_agg(jsonb_build_object('codeId', code.id, 'codeHint', code.code_hint)
        order by code.created_at, code.id) from platform.redemption_codes as code where code.batch_id = batch_row.id)
    );
    before_summary := jsonb_build_object('id', batch_row.id, 'status', 'draft', 'quantity', batch_row.quantity);
    after_summary := jsonb_build_object('id', batch_row.id, 'status', batch_row.status,
      'quantity', batch_row.quantity, 'issuedCount', batch_row.quantity);
  elsif p_action = 'pause_redemption_batch' then
    if p_resource_id is null or p_payload <> '{}'::jsonb then
      raise exception using errcode = '22023', message = 'Pause does not accept additional fields';
    end if;
    select batch.* into batch_row from platform.redemption_batches as batch where batch.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Redemption batch was not found'; end if;
    if batch_row.status <> 'active' then
      raise exception using errcode = '23514', message = 'Only active Redemption batches can be paused';
    end if;
    before_summary := jsonb_build_object('id', batch_row.id, 'status', batch_row.status);
    update platform.redemption_batches set status = 'paused' where id = batch_row.id;
    result := jsonb_build_object('batchId', batch_row.id, 'status', 'paused');
    after_summary := jsonb_build_object('id', batch_row.id, 'status', 'paused');
    target_id := batch_row.id;
  elsif p_action = 'close_redemption_batch' then
    if p_resource_id is null or p_payload <> '{}'::jsonb then
      raise exception using errcode = '22023', message = 'Close does not accept additional fields';
    end if;
    select batch.* into batch_row from platform.redemption_batches as batch where batch.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Redemption batch was not found'; end if;
    if batch_row.status not in ('active', 'paused') then
      raise exception using errcode = '23514', message = 'Only active or paused Redemption batches can be closed';
    end if;
    before_summary := jsonb_build_object('id', batch_row.id, 'status', batch_row.status);
    update platform.redemption_batches set status = 'closed' where id = batch_row.id;
    result := jsonb_build_object('batchId', batch_row.id, 'status', 'closed');
    after_summary := jsonb_build_object('id', batch_row.id, 'status', 'closed');
    target_id := batch_row.id;
  end if;

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('admin', p_actor_id, 'redemption.' || p_action, target_type, target_id, p_request_id, p_reason,
     before_summary, coalesce(after_summary, '{}'::jsonb))
  returning id into audit_id_value;
  result := result || jsonb_build_object('auditLogId', audit_id_value);
  update platform.idempotency_records
     set status = 'completed', resource_type = target_type, resource_id = target_id,
         response_status = 200, response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;

comment on function public.admin_redemption_command(uuid, text, uuid, jsonb, text, text, text, uuid) is
  'Executes explicit audited Redemption batch lifecycle and code generation commands without storing plaintext.';

revoke all on function public.admin_redemption_command(uuid, text, uuid, jsonb, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_redemption_command(uuid, text, uuid, jsonb, text, text, text, uuid)
  to service_role;
