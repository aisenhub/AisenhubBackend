-- OrderItem refunds are the smallest Commerce refund command. Admin callers use
-- the idempotent wrapper; the four-argument domain function remains reusable by
-- trusted internal jobs and is covered by the Commerce state specification.

create or replace function public.refund_order_item(
  p_order_item_id uuid,
  p_amount bigint,
  p_mode text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  item_row platform.order_items%rowtype;
  order_row platform.orders%rowtype;
  payment_row platform.payments%rowtype;
  grant_row platform.entitlement_grants%rowtype;
  revoke_result record;
  now_value timestamptz := timezone('utc', now());
  remaining_amount bigint;
  new_refunded_amount bigint;
  total_refunded_amount bigint;
  all_items_refunded boolean;
  payment_status_value text;
  order_status_value text;
  audit_id_value uuid := gen_random_uuid();
  result jsonb;
begin
  if p_order_item_id is null or p_amount is null or p_amount <= 0
     or p_mode not in ('compensation', 'return')
     or p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'The OrderItem refund request is invalid';
  end if;

  select item.*
    into item_row
    from platform.order_items as item
   where item.id = p_order_item_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The OrderItem was not found';
  end if;

  select order_fact.*
    into order_row
    from platform.orders as order_fact
   where order_fact.id = item_row.order_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The Order was not found';
  end if;

  if order_row.status not in ('fulfilled', 'partially_refunded') then
    raise exception using errcode = 'P0001', message = 'The Order is not eligible for a refund';
  end if;

  select payment.*
    into payment_row
    from platform.payments as payment
   where payment.order_id = order_row.id
     and payment.status in ('succeeded', 'partially_refunded', 'refunded')
   order by payment.created_at, payment.id
   limit 1
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'A refundable payment was not found';
  end if;

  remaining_amount := item_row.total_amount - item_row.refunded_amount;
  if p_amount > remaining_amount then
    raise exception using errcode = 'P0001', message = 'The refund exceeds the OrderItem total';
  end if;
  if p_mode = 'return' and p_amount <> remaining_amount then
    raise exception using errcode = 'P0001', message = 'A product return must refund the complete remaining OrderItem amount';
  end if;
  if item_row.fulfillment_status <> 'granted' then
    raise exception using errcode = 'P0001', message = 'Only granted OrderItems can be refunded';
  end if;

  if p_mode = 'return' then
    select entitlement.*
      into grant_row
      from platform.entitlement_grants as entitlement
     where entitlement.source_type = 'order_item'
       and entitlement.source_id = item_row.id
       and entitlement.status = 'active'
     for update;
    if not found then
      raise exception using errcode = 'P0001', message = 'The OrderItem entitlement is not active';
    end if;

    select *
      into revoke_result
      from public.revoke_entitlement(
        grant_row.id,
        'system',
        null,
        p_reason,
        null
      );
  end if;

  new_refunded_amount := item_row.refunded_amount + p_amount;
  update platform.order_items
     set refunded_amount = new_refunded_amount,
         fulfillment_status = case when p_mode = 'return' then 'revoked' else fulfillment_status end
   where id = item_row.id;

  select coalesce(sum(item.refunded_amount), 0), bool_and(item.refunded_amount = item.total_amount)
    into total_refunded_amount, all_items_refunded
    from platform.order_items as item
   where item.order_id = order_row.id;

  if total_refunded_amount >= payment_row.amount then
    payment_status_value := 'refunded';
    update platform.payments
       set status = 'refunded',
           refunded_at = coalesce(payment_row.refunded_at, now_value)
     where id = payment_row.id;
  else
    payment_status_value := 'partially_refunded';
    update platform.payments
       set status = 'partially_refunded',
           refunded_at = coalesce(payment_row.refunded_at, now_value)
     where id = payment_row.id;
  end if;

  if all_items_refunded then
    order_status_value := 'refunded';
    update platform.orders
       set status = 'refunded',
           refunded_at = coalesce(order_row.refunded_at, now_value)
     where id = order_row.id;
  else
    order_status_value := 'partially_refunded';
    update platform.orders
       set status = 'partially_refunded'
     where id = order_row.id;
  end if;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'system', null, 'commerce.refund_order_item', 'order_item', item_row.id,
     p_reason,
     jsonb_build_object(
       'orderStatus', order_row.status,
       'paymentStatus', payment_row.status,
       'refundedAmount', item_row.refunded_amount,
       'fulfillmentStatus', item_row.fulfillment_status
     ),
     jsonb_build_object(
       'orderStatus', order_status_value,
       'paymentStatus', payment_status_value,
       'refundedAmount', new_refunded_amount,
       'fulfillmentStatus', case when p_mode = 'return' then 'revoked' else item_row.fulfillment_status end,
       'mode', p_mode,
       'grantId', case when p_mode = 'return' then grant_row.id else null end
     ));

  result := jsonb_build_object(
    'itemId', item_row.id,
    'orderId', order_row.id,
    'refundedAmount', new_refunded_amount,
    'mode', p_mode,
    'orderStatus', order_status_value,
    'paymentStatus', payment_status_value,
    'grantId', case when p_mode = 'return' then grant_row.id else null end,
    'domainAuditLogId', audit_id_value
  );
  return result;
end;
$$;

comment on function public.refund_order_item(uuid, bigint, text, text) is
  'Atomically refunds one OrderItem, retaining or revoking its sourced entitlement according to explicit mode.';

create or replace function public.admin_refund_order_item(
  p_actor_id uuid,
  p_order_item_id uuid,
  p_amount bigint,
  p_mode text,
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
  domain_result jsonb;
  item_row platform.order_items%rowtype;
  audit_id_value uuid;
  result jsonb;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role is null or actor_role not in ('owner', 'admin', 'finance') then
    raise exception using errcode = '42501', message = 'OrderItem refunds require authorized Admin access';
  end if;
  if p_actor_id is null or p_order_item_id is null or p_request_id is null
     or p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'The Admin refund request is invalid';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.order_item.refund', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.order_item.refund'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0011', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body || jsonb_build_object('idempotent', true);
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The refund is already in progress';
    end if;
  end if;

  select item.*
    into item_row
    from platform.order_items as item
   where item.id = p_order_item_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The OrderItem was not found';
  end if;
  if p_amount is not null and p_amount > item_row.total_amount - item_row.refunded_amount then
    raise exception using errcode = 'P0008', message = 'The refund exceeds the OrderItem total';
  end if;

  domain_result := public.refund_order_item(p_order_item_id, p_amount, p_mode, p_reason);

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('admin', p_actor_id, 'order_items.refund', 'order_item', p_order_item_id, p_request_id, p_reason,
     jsonb_build_object('orderId', item_row.order_id, 'refundAmount', item_row.refunded_amount),
     domain_result || jsonb_build_object('requestId', p_request_id))
  returning id into audit_id_value;

  result := domain_result || jsonb_build_object(
    'auditLogId', audit_id_value,
    'idempotent', false,
    'overviewPath', '/v1/admin/orders/' || item_row.order_id::text || '/overview',
    'auditPath', '/v1/admin/audit-logs/' || audit_id_value::text
  );

  update platform.idempotency_records
     set status = 'completed',
         resource_type = 'order_item',
         resource_id = p_order_item_id,
         response_status = 200,
         response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;

comment on function public.admin_refund_order_item(uuid, uuid, bigint, text, text, text, text, uuid) is
  'Runs an idempotent Admin OrderItem refund command with role enforcement and append-only audit.';

revoke all on function public.refund_order_item(uuid, bigint, text, text)
  from public, anon, authenticated;
revoke all on function public.admin_refund_order_item(uuid, uuid, bigint, text, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.refund_order_item(uuid, bigint, text, text) to service_role;
grant execute on function public.admin_refund_order_item(uuid, uuid, bigint, text, text, text, text, uuid)
  to service_role;
