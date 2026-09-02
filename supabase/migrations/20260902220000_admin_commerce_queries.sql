-- Read-only Commerce projections. All fields are explicitly selected and
-- payment/event payloads are intentionally excluded from the API shape.

create or replace function public.admin_query_commerce_resource(
  p_actor_id uuid,
  p_resource text,
  p_cursor text default null,
  p_limit integer default 25,
  p_search text default null,
  p_status text default null,
  p_sort text default 'createdAt',
  p_direction text default 'desc'
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  cursor_value text;
  cursor_id uuid;
  cursor_json jsonb;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if actor_role is null then
    raise exception using errcode = '42501', message = 'Active Admin membership is required';
  end if;
  if p_resource not in ('orders', 'payments') then
    raise exception using errcode = '22023', message = 'The Commerce resource is not supported';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'The Commerce page size is invalid';
  end if;
  if p_direction not in ('asc', 'desc') then
    raise exception using errcode = '22023', message = 'The Commerce sort direction is invalid';
  end if;
  if p_search is not null and (length(p_search) < 1 or length(p_search) > 200) then
    raise exception using errcode = '22023', message = 'The Commerce search value is invalid';
  end if;
  if p_cursor is not null then
    begin
      cursor_json := convert_from(decode(p_cursor, 'base64'), 'utf8')::jsonb;
      cursor_value := cursor_json ->> 'value';
      cursor_id := (cursor_json ->> 'id')::uuid;
    exception when others then
      raise exception using errcode = '22023', message = 'The Commerce cursor is invalid';
    end;
  end if;

  if p_resource = 'orders' then
    if p_sort not in ('createdAt', 'status', 'amountTotal', 'orderNo') then
      raise exception using errcode = '22023', message = 'The Order sort field is invalid';
    end if;
    return (
      with base as (
        select order_fact.id,
               order_fact.order_no,
               case when actor_role = 'finance' then null else order_fact.user_id end as user_id,
               order_fact.customer_ref,
               order_fact.status,
               order_fact.currency,
               order_fact.amount_total,
               order_fact.channel,
               count(item.id)::integer as item_count,
               order_fact.created_at,
               order_fact.paid_at,
               order_fact.fulfilled_at,
               order_fact.cancelled_at,
               order_fact.refunded_at,
               case p_sort
                 when 'status' then order_fact.status
                 when 'amountTotal' then lpad(order_fact.amount_total::text, 20, '0')
                 when 'orderNo' then order_fact.order_no
                 else to_char(order_fact.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
               end as sort_value
          from platform.orders as order_fact
          left join platform.order_items as item on item.order_id = order_fact.id
         where (p_search is null or order_fact.order_no ilike '%' || p_search || '%' or order_fact.id::text ilike '%' || p_search || '%')
           and (p_status is null or order_fact.status = p_status)
         group by order_fact.id
      ), filtered as (
        select row_number() over (
                 order by case when p_direction = 'asc' then sort_value end asc,
                          case when p_direction = 'desc' then sort_value end desc,
                          case when p_direction = 'asc' then id end asc,
                          case when p_direction = 'desc' then id end desc
               ) - 1 as row_number,
               base.*
          from base
         where cursor_value is null
            or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit),
      next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object(
        'items', coalesce((select jsonb_agg(jsonb_build_object(
          'id', id, 'orderNo', order_no, 'userId', user_id, 'customerRef', customer_ref,
          'status', status, 'currency', currency, 'amountTotal', amount_total, 'channel', channel,
          'itemCount', item_count, 'createdAt', created_at, 'paidAt', paid_at,
          'fulfilledAt', fulfilled_at, 'cancelledAt', cancelled_at, 'refundedAt', refunded_at
        ) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object(
          'hasMore', exists(select 1 from next_row),
          'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)
        )
      )
    );
  end if;

  if p_sort not in ('createdAt', 'status', 'amount') then
    raise exception using errcode = '22023', message = 'The Payment sort field is invalid';
  end if;
  return (
    with base as (
      select payment.id, payment.provider, payment.status, payment.currency, payment.amount,
             payment.failure_code, payment.paid_at, payment.refunded_at, payment.disputed_at,
             payment.failed_at, payment.created_at,
             case p_sort
               when 'status' then payment.status
               when 'amount' then lpad(payment.amount::text, 20, '0')
               else to_char(payment.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
             end as sort_value
        from platform.payments as payment
       where (p_search is null or payment.provider ilike '%' || p_search || '%' or payment.id::text ilike '%' || p_search || '%')
         and (p_status is null or payment.status = p_status)
    ), filtered as (
      select row_number() over (
               order by case when p_direction = 'asc' then sort_value end asc,
                        case when p_direction = 'desc' then sort_value end desc,
                        case when p_direction = 'asc' then id end asc,
                        case when p_direction = 'desc' then id end desc
             ) - 1 as row_number,
             base.*
        from base
       where cursor_value is null
          or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
          or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
    ), selected as (select * from filtered where row_number < p_limit),
    next_row as (select * from filtered where row_number = p_limit limit 1)
    select jsonb_build_object(
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'provider', provider, 'status', status, 'currency', currency, 'amount', amount,
        'failureCode', failure_code, 'paidAt', paid_at, 'refundedAt', refunded_at,
        'disputedAt', disputed_at, 'failedAt', failed_at
      ) order by row_number) from selected), '[]'::jsonb),
      'page', jsonb_build_object(
        'hasMore', exists(select 1 from next_row),
        'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)
      )
    )
  );
end;
$$;

create or replace function public.admin_order_overview(
  p_actor_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  order_row platform.orders%rowtype;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if actor_role is null then
    raise exception using errcode = '42501', message = 'Active Admin membership is required';
  end if;
  if p_order_id is null then
    raise exception using errcode = '22023', message = 'An Order ID is required';
  end if;
  select order_fact.* into order_row
    from platform.orders as order_fact
   where order_fact.id = p_order_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'The Order was not found';
  end if;

  return jsonb_build_object(
    'order', jsonb_build_object(
      'id', order_row.id,
      'orderNo', order_row.order_no,
      'userId', case when actor_role = 'finance' then null else order_row.user_id end,
      'customerRef', order_row.customer_ref,
      'status', order_row.status,
      'currency', order_row.currency,
      'amountTotal', order_row.amount_total,
      'channel', order_row.channel,
      'itemCount', (select count(*)::integer from platform.order_items where order_id = order_row.id),
      'createdAt', order_row.created_at,
      'paidAt', order_row.paid_at,
      'fulfilledAt', order_row.fulfilled_at,
      'cancelledAt', order_row.cancelled_at,
      'refundedAt', order_row.refunded_at
    ),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', item.id,
        'productSku', item.sku_snapshot,
        'productName', item.product_name,
        'productVersion', version.version,
        'quantity', item.quantity,
        'unitAmount', item.unit_amount,
        'totalAmount', item.total_amount,
        'salesTerms', item.sales_terms,
        'fulfillmentStatus', item.fulfillment_status,
        'refundedAmount', item.refunded_amount,
        'grantId', grant_row.id,
        'grantStatus', grant_row.status
      ) order by item.created_at, item.id)
        from platform.order_items as item
        join platform.product_versions as version on version.id = item.product_version_id
        left join lateral (
          select grant_item.id, grant_item.status
            from platform.entitlement_grants as grant_item
           where grant_item.source_type = 'order_item' and grant_item.source_id = item.id
           order by grant_item.created_at desc, grant_item.id desc
           limit 1
        ) as grant_row on true
       where item.order_id = order_row.id
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', payment.id, 'provider', payment.provider, 'status', payment.status,
        'currency', payment.currency, 'amount', payment.amount, 'failureCode', payment.failure_code,
        'paidAt', payment.paid_at, 'refundedAt', payment.refunded_at,
        'disputedAt', payment.disputed_at, 'failedAt', payment.failed_at
      ) order by payment.created_at, payment.id)
        from platform.payments as payment where payment.order_id = order_row.id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', event.id, 'provider', event.provider, 'eventType', event.event_type,
        'status', event.status, 'currency', event.currency, 'amount', event.amount,
        'occurredAt', event.occurred_at, 'processedAt', event.processed_at
      ) order by event.occurred_at, event.id)
        from platform.payment_events as event where event.order_id = order_row.id
    ), '[]'::jsonb),
    'refunds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', audit.id, 'orderId', order_row.id, 'orderItemId', audit.target_id,
        'amountMinor', (audit.after_summary ->> 'refundedAmount')::bigint,
        'mode', audit.after_summary ->> 'mode', 'reason', audit.reason, 'createdAt', audit.created_at
      ) order by audit.created_at, audit.id)
        from platform.audit_logs as audit
       where audit.action = 'order_items.refund'
         and audit.target_type = 'order_item'
         and exists (select 1 from platform.order_items where id = audit.target_id and order_id = order_row.id)
    ), '[]'::jsonb),
    'exceptions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', audit.id, 'orderId', order_row.id, 'paymentId', event.payment_id,
        'paymentEventId', event.id,
        'type', case when audit.action = 'commerce.payment_exception' then 'late_payment_after_cancel' else 'ignored_event' end,
        'reason', audit.reason, 'createdAt', audit.created_at
      ) order by audit.created_at, audit.id)
        from platform.audit_logs as audit
        join platform.payment_events as event on event.id = audit.request_id
       where audit.action in ('commerce.payment_exception', 'commerce.payment_event_ignored')
         and audit.target_type = 'order' and audit.target_id = order_row.id
    ), '[]'::jsonb),
    'auditTimeline', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', audit.id, 'actorType', audit.actor_type, 'actorId', audit.actor_id,
        'action', audit.action, 'targetType', audit.target_type, 'targetId', audit.target_id,
        'requestId', audit.request_id, 'reason', audit.reason,
        'beforeSummary', audit.before_summary, 'afterSummary', audit.after_summary,
        'createdAt', audit.created_at
      ) order by audit.created_at, audit.id)
        from platform.audit_logs as audit
       where (audit.target_type = 'order' and audit.target_id = order_row.id)
          or (audit.target_type = 'order_item' and exists (
                select 1 from platform.order_items where id = audit.target_id and order_id = order_row.id
             ))
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.admin_query_commerce_resource(uuid, text, text, integer, text, text, text, text) is
  'Returns role-filtered, paginated Order and Payment projections without provider credentials or event payloads.';
comment on function public.admin_order_overview(uuid, uuid) is
  'Returns one role-filtered Order 360 aggregate including item grants, refunds, exceptions, safe payment/event summaries, and audit timeline.';

revoke all on function public.admin_query_commerce_resource(uuid, text, text, integer, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.admin_order_overview(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_query_commerce_resource(uuid, text, text, integer, text, text, text, text)
  to service_role;
grant execute on function public.admin_order_overview(uuid, uuid) to service_role;
