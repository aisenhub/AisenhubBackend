-- Safe, fixed-shape Admin operational summaries.
-- This is intentionally an allowlisted aggregate, not a generic BI or SQL surface.

create or replace function public.admin_operations_overview(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  pending_orders bigint;
  paid_orders bigint;
  chargeback_orders bigint;
  deletion_queue bigint;
  open_feedback bigint;
  cards jsonb := '[]'::jsonb;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';

  if actor_role is null then
    raise exception using errcode = '42501', message = 'Active Admin membership is required';
  end if;

  select count(*) into pending_orders
    from platform.orders as order_item
   where order_item.status = 'pending';

  select count(*) into paid_orders
    from platform.orders as order_item
   where order_item.status = 'paid';

  select count(*) into chargeback_orders
    from platform.orders as order_item
   where order_item.status = 'chargeback';

  select count(*) into deletion_queue
    from platform.profiles as profile
   where profile.status = 'deletion_pending';

  if actor_role in ('owner', 'admin', 'support') then
    select count(*) into open_feedback
      from platform.feedback_requests as feedback
     where feedback.status = 'open';
  end if;

  cards := cards || jsonb_build_array(
    jsonb_build_object(
      'key', 'pending-orders',
      'label', 'Pending orders',
      'count', pending_orders,
      'severity', case when pending_orders > 0 then 'attention' else 'neutral' end,
      'href', '/orders?status=pending'
    ),
    jsonb_build_object(
      'key', 'paid-orders',
      'label', 'Paid orders awaiting fulfillment',
      'count', paid_orders,
      'severity', case when paid_orders > 0 then 'attention' else 'neutral' end,
      'href', '/orders?status=paid'
    ),
    jsonb_build_object(
      'key', 'deletion-queue',
      'label', 'Accounts awaiting deletion',
      'count', deletion_queue,
      'severity', case when deletion_queue > 0 then 'attention' else 'neutral' end,
      'href', '/users?status=deletion_pending'
    )
  );

  if actor_role in ('owner', 'admin', 'finance') then
    cards := cards || jsonb_build_array(
      jsonb_build_object(
        'key', 'chargeback-orders',
        'label', 'Chargeback orders',
        'count', chargeback_orders,
        'severity', case when chargeback_orders > 0 then 'critical' else 'neutral' end,
        'href', '/orders?status=chargeback'
      )
    );
  end if;

  if actor_role in ('owner', 'admin', 'support') then
    cards := cards || jsonb_build_array(
      jsonb_build_object(
        'key', 'open-feedback',
        'label', 'Open feedback',
        'count', open_feedback,
        'severity', case when open_feedback > 0 then 'attention' else 'neutral' end,
        'href', '/feedback?status=open'
      )
    );
  end if;

  return jsonb_build_object(
    'generatedAt', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'cards', cards
  );
end;
$$;

comment on function public.admin_operations_overview(uuid) is
  'Returns fixed, role-filtered operational counts and fixed Admin drill-down paths without PII or arbitrary query input.';

revoke all on function public.admin_operations_overview(uuid) from public, anon, authenticated;
grant execute on function public.admin_operations_overview(uuid) to service_role;
