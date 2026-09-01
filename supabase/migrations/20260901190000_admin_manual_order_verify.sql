-- Finance/Owner manual payment verification. The command records a minimized
-- internal payment event and delegates all fulfillment to the shared domain function.

create or replace function public.admin_verify_order(
  p_actor_id uuid,
  p_order_id uuid,
  p_payment_reference text,
  p_amount bigint,
  p_currency text,
  p_reason text,
  p_idempotency_key text,
  p_request_hash text,
  p_request_id uuid
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
  order_row platform.orders%rowtype;
  payment_row platform.payments%rowtype;
  fulfillment_result jsonb;
  fulfillment_audit_id uuid;
  audit_id_value uuid;
  event_id_value uuid := gen_random_uuid();
  now_value timestamptz := timezone('utc', now());
  external_event_id_value text := 'manual-' || replace(p_request_id::text, '-', '');
  result jsonb;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';

  if actor_role is null or actor_role not in ('owner', 'finance') then
    raise exception using errcode = '42501', message = 'Manual order verification requires Finance or Owner access';
  end if;
  if p_order_id is null or p_actor_id is null or p_request_id is null then
    raise exception using errcode = '22023', message = 'Manual order verification identity is invalid';
  end if;
  if p_payment_reference is null
     or btrim(p_payment_reference) = ''
     or length(p_payment_reference) > 200
     or p_payment_reference ~ '[[:space:]]'
     or p_amount is null
     or p_amount < 0
     or p_currency is null
     or p_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'Manual payment evidence is invalid';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A manual verification reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.order.verify', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     now_value + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.order.verify'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body || jsonb_build_object('idempotent', true);
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The manual verification is already in progress';
    end if;
  end if;

  select order_fact.*
    into order_row
    from platform.orders as order_fact
   where order_fact.id = p_order_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The order was not found';
  end if;
  if order_row.channel <> 'manual' or order_row.status <> 'pending' then
    raise exception using errcode = 'P0004', message = 'The order is not eligible for manual verification';
  end if;

  select payment.*
    into payment_row
    from platform.payments as payment
   where payment.order_id = order_row.id
     and payment.status = 'pending'
   order by payment.created_at, payment.id
   limit 1
   for update;
  if not found then
    raise exception using errcode = 'P0006', message = 'A pending payment was not found for the order';
  end if;
  if payment_row.provider <> 'manual'
     or payment_row.external_payment_id is distinct from p_payment_reference then
    raise exception using errcode = 'P0005', message = 'The manual payment reference does not match the order payment';
  end if;
  if payment_row.amount <> p_amount or payment_row.currency <> p_currency
     or order_row.amount_total <> p_amount or order_row.currency <> p_currency then
    raise exception using errcode = 'P0003', message = 'The manual payment amount or currency does not match the order';
  end if;

  insert into platform.payment_events
    (id, payment_id, order_id, provider, external_event_id, event_type, status,
     currency, amount, payload_summary, occurred_at, created_at, updated_at)
  values
    (event_id_value, payment_row.id, order_row.id, 'manual', external_event_id_value,
     'payment.succeeded', 'received', p_currency, p_amount,
     jsonb_build_object(
       'channel', 'manual',
       'paymentReference', p_payment_reference,
       'amountMinor', p_amount,
       'currency', p_currency
     ),
     now_value, now_value, now_value);

  select public.fulfill_paid_order(event_id_value)
    into fulfillment_result;

  select audit.id
    into fulfillment_audit_id
    from platform.audit_logs as audit
   where audit.action = 'commerce.fulfill_paid_order'
     and audit.target_type = 'order'
     and audit.target_id = order_row.id
     and audit.request_id = event_id_value
   order by audit.created_at desc, audit.id desc
   limit 1;
  if fulfillment_audit_id is null then
    raise exception using errcode = 'P0007', message = 'The fulfillment audit record was not created';
  end if;

  result := jsonb_build_object(
    'orderId', order_row.id,
    'paymentId', payment_row.id,
    'paymentEventId', event_id_value,
    'status', 'fulfilled',
    'grantIds', coalesce(fulfillment_result->'grantIds', '[]'::jsonb),
    'idempotent', false,
    'fulfillmentAuditLogId', fulfillment_audit_id,
    'overviewPath', '/v1/admin/orders/' || order_row.id::text || '/overview'
  );

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('admin', p_actor_id, 'orders.verify', 'order', order_row.id, p_request_id, p_reason,
     jsonb_build_object('orderStatus', 'pending', 'paymentStatus', 'pending', 'channel', order_row.channel),
     jsonb_build_object('orderStatus', 'fulfilled', 'paymentStatus', 'succeeded',
                        'paymentEventId', event_id_value, 'fulfillmentAuditLogId', fulfillment_audit_id))
  returning id into audit_id_value;

  result := result || jsonb_build_object(
    'auditLogId', audit_id_value,
    'auditPath', '/v1/admin/audit-logs/' || audit_id_value::text
  );

  update platform.idempotency_records
     set status = 'completed',
         resource_type = 'order',
         resource_id = order_row.id,
         response_status = 200,
         response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;

comment on function public.admin_verify_order(uuid, uuid, text, bigint, text, text, text, text, uuid) is
  'Verifies a manual payment as an audited Admin command and delegates fulfillment to the shared atomic domain function.';

revoke all on function public.admin_verify_order(uuid, uuid, text, bigint, text, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_verify_order(uuid, uuid, text, bigint, text, text, text, text, uuid)
  to service_role;
