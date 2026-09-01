-- Atomic and idempotent redemption transaction.

create or replace function public.redeem_code(
  p_code_hash text,
  p_user_id uuid,
  p_idempotency_key text,
  p_request_hash text,
  p_ip_hash text default null
)
returns table (
  redemption_id uuid,
  code_id uuid,
  batch_id uuid,
  grant_id uuid,
  status text,
  idempotency_record_id uuid,
  redeemed_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
declare
  idempotency_row platform.idempotency_records%rowtype;
  code_row platform.redemption_codes%rowtype;
  batch_row platform.redemption_batches%rowtype;
  version_row platform.product_versions%rowtype;
  existing_redemption platform.redemptions%rowtype;
  grant_result record;
  redemption_id_value uuid := gen_random_uuid();
  audit_id_value uuid := gen_random_uuid();
  now_value timestamptz := timezone('utc', now());
  response_body_value jsonb;
begin
  if p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = '23514',
      message = 'A normalized redemption code hash is required';
  end if;

  if p_user_id is null or p_idempotency_key is null or btrim(p_idempotency_key) = ''
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using
      errcode = '23514',
      message = 'Redemption identity and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('redemption', 'user:' || p_user_id::text, p_idempotency_key, p_request_hash, now_value + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if not found then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'redemption'
       and record.actor_key = 'user:' || p_user_id::text
       and record.idempotency_key = p_idempotency_key
     for update;

    if idempotency_row.request_hash <> p_request_hash then
      raise exception using
        errcode = '23505',
        message = 'The idempotency key was already used for another request';
    end if;

    if idempotency_row.status = 'completed' then
      return query
      select (idempotency_row.response_body ->> 'redemptionId')::uuid,
             (idempotency_row.response_body ->> 'codeId')::uuid,
             (idempotency_row.response_body ->> 'batchId')::uuid,
             (idempotency_row.response_body ->> 'grantId')::uuid,
             idempotency_row.response_body ->> 'status',
             idempotency_row.id,
             (idempotency_row.response_body ->> 'redeemedAt')::timestamptz;
      return;
    end if;
  end if;

  select code.*
    into code_row
    from platform.redemption_codes as code
   where code.code_hash = p_code_hash
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'The redemption code is unavailable';
  end if;

  if code_row.status <> 'issued' then
    select redemption.*
      into existing_redemption
      from platform.redemptions as redemption
     where redemption.code_id = code_row.id;

    if code_row.status = 'redeemed'
       and found
       and existing_redemption.user_id = p_user_id then
      response_body_value := jsonb_build_object(
        'redemptionId', existing_redemption.id,
        'codeId', existing_redemption.code_id,
        'batchId', existing_redemption.batch_id,
        'grantId', existing_redemption.grant_id,
        'status', 'redeemed',
        'redeemedAt', existing_redemption.redeemed_at
      );
      update platform.idempotency_records
      set status = 'completed',
          resource_type = 'redemption',
          resource_id = existing_redemption.id,
          response_status = 200,
          response_body = response_body_value
      where id = idempotency_row.id;

      return query
      select existing_redemption.id, existing_redemption.code_id, existing_redemption.batch_id,
             existing_redemption.grant_id, 'redeemed', idempotency_row.id,
             existing_redemption.redeemed_at;
      return;
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'The redemption code is unavailable';
  end if;

  select batch.*
    into batch_row
    from platform.redemption_batches as batch
   where batch.id = code_row.batch_id
   for update;

  if not found
     or batch_row.status <> 'active'
     or batch_row.starts_at > now_value
     or (batch_row.expires_at is not null and batch_row.expires_at <= now_value) then
    raise exception using
      errcode = 'P0001',
      message = 'The redemption code is unavailable';
  end if;

  select version.*
    into version_row
    from platform.product_versions as version
   where version.id = batch_row.product_version_id
     and version.product_id = batch_row.product_id
   for update;

  if not found or version_row.status <> 'published' then
    raise exception using
      errcode = 'P0001',
      message = 'The redemption code is unavailable';
  end if;

  if (select count(*)
      from platform.redemptions as redemption
     where redemption.batch_id = batch_row.id
       and redemption.user_id = p_user_id)
     >= batch_row.per_user_limit then
    raise exception using
      errcode = 'P0001',
      message = 'The redemption code is unavailable';
  end if;

  select * into grant_result
  from public.grant_entitlement(
    p_user_id,
    version_row.id,
    'redemption',
    redemption_id_value,
    now_value,
    batch_row.expires_at,
    'system',
    null,
    'Redemption code redeemed',
    null,
    null
  );

  insert into platform.redemptions
    (id, code_id, batch_id, user_id, grant_id, idempotency_record_id, ip_hash, redeemed_at)
  values
    (redemption_id_value, code_row.id, batch_row.id, p_user_id, grant_result.grant_id,
     idempotency_row.id, p_ip_hash, now_value);

  update platform.redemption_codes
  set status = 'redeemed', redeemed_at = now_value
  where id = code_row.id;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'user', p_user_id, 'redemptions.redeem', 'redemption', redemption_id_value,
     null, 'Redemption code redeemed', '{}'::jsonb,
     jsonb_build_object('redemptionId', redemption_id_value, 'codeId', code_row.id, 'batchId', batch_row.id));

  response_body_value := jsonb_build_object(
    'redemptionId', redemption_id_value,
    'codeId', code_row.id,
    'batchId', batch_row.id,
    'grantId', grant_result.grant_id,
    'status', 'redeemed',
    'redeemedAt', now_value
  );
  update platform.idempotency_records
  set status = 'completed',
      resource_type = 'redemption',
      resource_id = redemption_id_value,
      response_status = 200,
      response_body = response_body_value
  where id = idempotency_row.id;

  return query
  select redemption_id_value, code_row.id, batch_row.id, grant_result.grant_id,
         'redeemed', idempotency_row.id, now_value;
end;
$$;

comment on function public.redeem_code(text, uuid, text, text, text) is
  'Atomically claims one hashed redemption code, creates its entitlement, records the receipt, and saves an idempotent result.';

revoke all on function public.redeem_code(text, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.redeem_code(text, uuid, text, text, text)
  to service_role;
