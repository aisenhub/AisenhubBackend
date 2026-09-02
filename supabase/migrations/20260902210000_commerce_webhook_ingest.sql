-- Provider-neutral signed webhook intake. The Edge Function verifies the
-- provider signature; this function owns event uniqueness and dispatch.

create or replace function public.receive_payment_webhook_event(
  p_payment_id uuid,
  p_order_id uuid,
  p_provider text,
  p_external_event_id text,
  p_event_type text,
  p_currency text,
  p_amount bigint,
  p_payload_summary jsonb,
  p_occurred_at timestamptz
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  event_id_value uuid;
  event_row platform.payment_events%rowtype;
  order_status_value text;
  fulfillment_result jsonb;
  now_value timestamptz := timezone('utc', now());
begin
  if p_payment_id is null or p_order_id is null or p_provider is null
     or p_external_event_id is null or p_event_type is null or p_currency is null
     or p_amount is null or p_payload_summary is null or p_occurred_at is null then
    raise exception using errcode = '22023', message = 'The payment webhook event is incomplete';
  end if;
  if p_occurred_at > now_value then
    raise exception using errcode = '22023', message = 'The payment webhook event is from the future';
  end if;

  insert into platform.payment_events
    (payment_id, order_id, provider, external_event_id, event_type, status,
     currency, amount, payload_summary, occurred_at)
  values
    (p_payment_id, p_order_id, p_provider, btrim(p_external_event_id), p_event_type, 'received',
     p_currency, p_amount, p_payload_summary, p_occurred_at)
  on conflict (provider, external_event_id) do nothing
  returning id into event_id_value;

  if event_id_value is null then
    select event.*
      into event_row
      from platform.payment_events as event
     where event.provider = p_provider
       and event.external_event_id = btrim(p_external_event_id)
     for update;
    if not found then
      raise exception using errcode = '40001', message = 'The payment webhook event can be retried';
    end if;
    if event_row.payment_id is distinct from p_payment_id
       or event_row.order_id is distinct from p_order_id
       or event_row.event_type is distinct from p_event_type
       or event_row.currency is distinct from p_currency
       or event_row.amount is distinct from p_amount
       or event_row.occurred_at is distinct from p_occurred_at
       or event_row.payload_summary is distinct from p_payload_summary then
      raise exception using errcode = '23514', message = 'The payment webhook event identity does not match';
    end if;
    if event_row.status = 'processed' then
      return jsonb_build_object(
        'status', 'processed',
        'orderId', event_row.order_id,
        'paymentId', event_row.payment_id,
        'paymentEventId', event_row.id,
        'idempotent', true
      );
    end if;
    if event_row.status = 'ignored' then
      return jsonb_build_object(
        'status', 'ignored',
        'orderId', event_row.order_id,
        'paymentId', event_row.payment_id,
        'paymentEventId', event_row.id,
        'idempotent', true
      );
    end if;
    event_id_value := event_row.id;
  end if;

  select order_fact.status
    into order_status_value
    from platform.orders as order_fact
   where order_fact.id = p_order_id
   for update;

  if p_event_type = 'payment.succeeded' and order_status_value = 'cancelled' then
    return public.record_paid_after_cancelled_order(
      event_id_value,
      'Payment succeeded after order cancellation'
    );
  end if;

  if p_event_type = 'payment.succeeded' and order_status_value = 'pending' then
    select public.fulfill_paid_order(event_id_value)
      into fulfillment_result;
    return fulfillment_result;
  end if;

  update platform.payment_events
     set status = 'ignored',
         processed_at = now_value
   where id = event_id_value;

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('webhook', null, 'commerce.payment_event_ignored', 'order', p_order_id, event_id_value,
     case
       when p_event_type <> 'payment.succeeded' then 'Unsupported payment event type'
       else 'Payment success arrived after the order was already resolved'
     end,
     jsonb_build_object('orderStatus', order_status_value, 'eventType', p_event_type),
     jsonb_build_object('eventStatus', 'ignored'));

  return jsonb_build_object(
    'status', 'ignored',
    'orderId', p_order_id,
    'paymentId', p_payment_id,
    'paymentEventId', event_id_value,
    'idempotent', false
  );
end;
$$;

comment on function public.receive_payment_webhook_event(uuid, uuid, text, text, text, text, bigint, jsonb, timestamptz) is
  'Atomically records a provider-neutral payment webhook event, deduplicates external identities, and dispatches safe fulfillment or exception handling.';

revoke all on function public.receive_payment_webhook_event(uuid, uuid, text, text, text, text, bigint, jsonb, timestamptz)
  from public, anon, authenticated;
grant execute on function public.receive_payment_webhook_event(uuid, uuid, text, text, text, text, bigint, jsonb, timestamptz)
  to service_role;
