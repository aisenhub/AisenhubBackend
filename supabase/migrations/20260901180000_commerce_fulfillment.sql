-- Atomic paid-order fulfillment. Refund and chargeback commands arrive later.

create or replace function public.fulfill_paid_order(p_payment_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
declare
  event_row platform.payment_events%rowtype;
  payment_row platform.payments%rowtype;
  order_row platform.orders%rowtype;
  item_row platform.order_items%rowtype;
  grant_result record;
  grant_ids jsonb := '[]'::jsonb;
  now_value timestamptz := timezone('utc', now());
begin
  select event.*
    into event_row
    from platform.payment_events as event
   where event.id = p_payment_event_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Payment event was not found';
  end if;

  select payment.*
    into payment_row
    from platform.payments as payment
   where payment.id = event_row.payment_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Payment was not found';
  end if;

  select order_fact.*
    into order_row
    from platform.orders as order_fact
   where order_fact.id = event_row.order_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Order was not found';
  end if;

  if payment_row.order_id <> order_row.id
     or payment_row.provider <> event_row.provider
     or payment_row.currency <> event_row.currency
     or payment_row.amount <> event_row.amount then
    raise exception using errcode = '23514', message = 'Payment event does not match its order';
  end if;

  if event_row.status = 'processed' then
    return jsonb_build_object(
      'status', 'fulfilled',
      'orderId', order_row.id,
      'paymentId', payment_row.id,
      'paymentEventId', event_row.id,
      'idempotent', true
    );
  end if;

  if event_row.event_type <> 'payment.succeeded' then
    raise exception using errcode = '23514', message = 'Only payment success events can fulfill orders';
  end if;

  if order_row.status <> 'pending' then
    raise exception using errcode = 'P0001', message = 'Only pending orders can be fulfilled';
  end if;
  if payment_row.status <> 'pending' then
    raise exception using errcode = 'P0001', message = 'Only pending payments can fulfill orders';
  end if;
  if order_row.user_id is null then
    raise exception using errcode = '23514', message = 'An order must retain a user for entitlement fulfillment';
  end if;

  for item_row in
    select item.*
      from platform.order_items as item
     where item.order_id = order_row.id
     order by item.id
     for update
  loop
    if item_row.fulfillment_status = 'revoked' then
      raise exception using errcode = 'P0001', message = 'Revoked order items cannot be fulfilled';
    end if;

    if item_row.fulfillment_status = 'pending' then
      select *
        into grant_result
        from public.grant_entitlement(
          order_row.user_id,
          item_row.product_version_id,
          'order_item',
          item_row.id,
          now_value,
          null,
          'webhook',
          null,
          'Payment event fulfillment for order item ' || item_row.id::text,
          null,
          event_row.id
        );

      update platform.order_items
         set fulfillment_status = 'granted'
       where id = item_row.id;
      grant_ids := grant_ids || jsonb_build_array(grant_result.grant_id);
    end if;
  end loop;

  update platform.payments
     set status = 'succeeded',
         paid_at = coalesce(payment_row.paid_at, now_value),
         failure_code = null
   where id = payment_row.id;

  update platform.orders
     set status = 'fulfilled',
         paid_at = coalesce(order_row.paid_at, now_value),
         fulfilled_at = now_value
   where id = order_row.id;

  update platform.payment_events
     set status = 'processed',
         processed_at = now_value
   where id = event_row.id;

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('webhook', null, 'commerce.fulfill_paid_order', 'order', order_row.id, event_row.id,
     'Payment event fulfillment',
     jsonb_build_object('orderStatus', order_row.status, 'paymentStatus', payment_row.status),
     jsonb_build_object('orderStatus', 'fulfilled', 'paymentStatus', 'succeeded', 'grantIds', grant_ids));

  return jsonb_build_object(
    'status', 'fulfilled',
    'orderId', order_row.id,
    'paymentId', payment_row.id,
    'paymentEventId', event_row.id,
    'grantIds', grant_ids,
    'idempotent', false
  );
end;
$$;

comment on function public.fulfill_paid_order(uuid) is
  'Atomically fulfills a pending order from one payment success event, granting each OrderItem independently and safely replaying processed events.';

revoke all on function public.fulfill_paid_order(uuid)
  from public, anon, authenticated;
grant execute on function public.fulfill_paid_order(uuid) to service_role;
