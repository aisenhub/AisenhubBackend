-- Dispute and late-payment handling stay inside the Commerce domain boundary.
-- No browser or Admin Data API caller can invoke these functions directly.

create or replace function public.chargeback_order(
  p_order_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  order_row platform.orders%rowtype;
  payment_row platform.payments%rowtype;
  item_row platform.order_items%rowtype;
  grant_row platform.entitlement_grants%rowtype;
  revoke_result record;
  grant_ids jsonb := '[]'::jsonb;
  now_value timestamptz := timezone('utc', now());
  audit_id_value uuid := gen_random_uuid();
begin
  if p_order_id is null or p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'The chargeback request is invalid';
  end if;

  select order_fact.*
    into order_row
    from platform.orders as order_fact
   where order_fact.id = p_order_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The Order was not found';
  end if;
  if order_row.status not in ('paid', 'fulfilled', 'partially_refunded') then
    raise exception using errcode = 'P0001', message = 'The Order is not eligible for a chargeback';
  end if;

  select payment.*
    into payment_row
    from platform.payments as payment
   where payment.order_id = order_row.id
     and payment.status in ('succeeded', 'partially_refunded')
   order by payment.created_at, payment.id
   limit 1
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'A disputed payment was not found';
  end if;

  for item_row in
    select item.*
      from platform.order_items as item
     where item.order_id = order_row.id
     order by item.id
     for update
  loop
    select entitlement.*
      into grant_row
      from platform.entitlement_grants as entitlement
     where entitlement.source_type = 'order_item'
       and entitlement.source_id = item_row.id
       and entitlement.status = 'active'
     for update;
    if found then
      select *
        into revoke_result
        from public.revoke_entitlement(grant_row.id, 'system', null, p_reason, null);
      update platform.order_items
         set fulfillment_status = 'revoked'
       where id = item_row.id;
      grant_ids := grant_ids || jsonb_build_array(revoke_result.grant_id);
    end if;
  end loop;

  update platform.payments
     set status = 'disputed',
         disputed_at = coalesce(payment_row.disputed_at, now_value),
         refunded_at = null
   where id = payment_row.id;

  update platform.orders
     set status = 'chargeback',
         fulfilled_at = coalesce(order_row.fulfilled_at, now_value)
   where id = order_row.id;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'system', null, 'commerce.chargeback_order', 'order', order_row.id, p_reason,
     jsonb_build_object('orderStatus', order_row.status, 'paymentStatus', payment_row.status),
     jsonb_build_object('orderStatus', 'chargeback', 'paymentStatus', 'disputed', 'grantIds', grant_ids));

  return jsonb_build_object(
    'status', 'chargeback',
    'orderId', order_row.id,
    'paymentId', payment_row.id,
    'grantIds', grant_ids,
    'auditLogId', audit_id_value,
    'idempotent', false
  );
end;
$$;

comment on function public.chargeback_order(uuid, text) is
  'Atomically marks an eligible Order as chargeback, disputes its payment, revokes all active OrderItem grants, and audits the outcome.';

create or replace function public.record_paid_after_cancelled_order(
  p_payment_event_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  event_row platform.payment_events%rowtype;
  order_row platform.orders%rowtype;
  payment_row platform.payments%rowtype;
  audit_id_value uuid := gen_random_uuid();
  now_value timestamptz := timezone('utc', now());
begin
  if p_payment_event_id is null or p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'The payment exception request is invalid';
  end if;

  select event.*
    into event_row
    from platform.payment_events as event
   where event.id = p_payment_event_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The payment event was not found';
  end if;
  if event_row.status = 'ignored' then
    return jsonb_build_object(
      'status', 'exception',
      'exceptionType', 'late_payment_after_cancel',
      'orderId', event_row.order_id,
      'paymentId', event_row.payment_id,
      'paymentEventId', event_row.id,
      'idempotent', true
    );
  end if;
  if event_row.status <> 'received' or event_row.event_type <> 'payment.succeeded' then
    raise exception using errcode = 'P0001', message = 'Only a received payment success event can become a late-payment exception';
  end if;

  select payment.*
    into payment_row
    from platform.payments as payment
   where payment.id = event_row.payment_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The payment was not found';
  end if;
  select order_fact.*
    into order_row
    from platform.orders as order_fact
   where order_fact.id = event_row.order_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The Order was not found';
  end if;
  if order_row.status <> 'cancelled' then
    raise exception using errcode = 'P0001', message = 'The payment event is not late for a cancelled Order';
  end if;

  update platform.payment_events
     set status = 'ignored',
         processed_at = now_value
   where id = event_row.id;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'webhook', null, 'commerce.payment_exception', 'order', order_row.id, event_row.id, p_reason,
     jsonb_build_object('orderStatus', order_row.status, 'paymentStatus', payment_row.status, 'paymentEventStatus', event_row.status),
     jsonb_build_object('exceptionType', 'late_payment_after_cancel', 'paymentEventId', event_row.id, 'status', 'ignored'));

  return jsonb_build_object(
    'status', 'exception',
    'exceptionType', 'late_payment_after_cancel',
    'orderId', order_row.id,
    'paymentId', payment_row.id,
    'paymentEventId', event_row.id,
    'auditLogId', audit_id_value,
    'idempotent', false
  );
end;
$$;

comment on function public.record_paid_after_cancelled_order(uuid, text) is
  'Records a paid event received after cancellation as an ignored, audited exception without fulfillment.';

revoke all on function public.chargeback_order(uuid, text)
  from public, anon, authenticated;
revoke all on function public.record_paid_after_cancelled_order(uuid, text)
  from public, anon, authenticated;
grant execute on function public.chargeback_order(uuid, text) to service_role;
grant execute on function public.record_paid_after_cancelled_order(uuid, text) to service_role;
