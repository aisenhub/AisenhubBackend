-- Customer and User 360 read models. These are backend aggregates over existing facts.

create or replace function public.admin_query_customer_resource(
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
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';

  if actor_role is null then
    raise exception using errcode = '42501', message = 'Active Admin membership is required';
  end if;
  if p_resource <> 'account-deletion-requests' then
    raise exception using errcode = '22023', message = 'The Customer resource is not supported';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'The Customer page size is invalid';
  end if;
  if p_direction not in ('asc', 'desc') then
    raise exception using errcode = '22023', message = 'The Customer sort direction is invalid';
  end if;
  if p_sort not in ('createdAt', 'status') then
    raise exception using errcode = '22023', message = 'The deletion request sort field is invalid';
  end if;
  if p_search is not null and (length(p_search) < 1 or length(p_search) > 200) then
    raise exception using errcode = '22023', message = 'The Customer search value is invalid';
  end if;

  if p_cursor is not null then
    begin
      cursor_json := convert_from(decode(p_cursor, 'base64'), 'utf8')::jsonb;
      cursor_value := cursor_json ->> 'value';
      cursor_id := (cursor_json ->> 'id')::uuid;
    exception when others then
      raise exception using errcode = '22023', message = 'The Customer cursor is invalid';
    end;
  end if;

  return (
    with base as (
      select request_item.id,
             request_item.user_id,
             request_item.status,
             request_item.execute_after,
             request_item.attempt_count,
             request_item.last_error_code,
             request_item.next_attempt_at,
             request_item.requested_at,
             request_item.completed_at,
             request_item.cancelled_at,
             case p_sort
               when 'status' then request_item.status
               else to_char(request_item.requested_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
             end as sort_value
        from platform.account_deletion_requests as request_item
       where (p_search is null
          or request_item.user_id::text ilike '%' || p_search || '%'
          or request_item.status ilike '%' || p_search || '%')
         and (p_status is null or request_item.status = p_status)
    ), filtered as (
      select row_number() over (
               order by
                 case when p_direction = 'asc' then sort_value end asc,
                 case when p_direction = 'desc' then sort_value end desc,
                 case when p_direction = 'asc' then id end asc,
                 case when p_direction = 'desc' then id end desc
             ) - 1 as row_number,
             base.*
        from base
       where cursor_value is null
          or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
          or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
    ), selected as (
      select * from filtered where row_number < p_limit
    ), next_row as (
      select * from filtered where row_number = p_limit limit 1
    )
    select jsonb_build_object(
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id,
        'userId', user_id,
        'status', status,
        'executeAfter', execute_after,
        'attemptCount', attempt_count,
        'lastErrorCode', last_error_code,
        'nextAttemptAt', next_attempt_at,
        'requestedAt', requested_at,
        'completedAt', completed_at,
        'cancelledAt', cancelled_at
      ) order by row_number) from selected), '[]'::jsonb),
      'page', jsonb_build_object(
        'hasMore', exists(select 1 from next_row),
        'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)
      )
    )
  );
end;
$$;

create or replace function public.admin_user_overview(
  p_actor_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, platform
as $$
declare
  actor_role text;
  profile_row platform.profiles%rowtype;
  target_admin_role text;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';

  if actor_role is null then
    raise exception using errcode = '42501', message = 'Active Admin membership is required';
  end if;
  if p_user_id is null then
    raise exception using errcode = '22023', message = 'A user ID is required';
  end if;

  select profile.*
    into profile_row
    from platform.profiles as profile
   where profile.id = p_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'The user profile was not found';
  end if;

  select member.role
    into target_admin_role
    from platform.admin_members as member
   where member.user_id = p_user_id
     and member.status = 'active';

  return jsonb_build_object(
    'profile', jsonb_build_object(
      'userId', profile_row.id,
      'displayName', case when actor_role = 'finance' then null else profile_row.display_name end,
      'avatarUrl', case when actor_role = 'finance' then null else profile_row.avatar_url end,
      'locale', case when actor_role = 'finance' then null else profile_row.locale end,
      'status', profile_row.status,
      'createdAt', profile_row.created_at,
      'updatedAt', profile_row.updated_at
    ),
    'adminRole', target_admin_role,
    'entitlements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', grant_item.id,
        'userId', grant_item.user_id,
        'productSku', product.sku,
        'productVersion', version.version,
        'sourceType', grant_item.source_type,
        'status', grant_item.status,
        'startsAt', grant_item.starts_at,
        'expiresAt', grant_item.expires_at,
        'createdAt', grant_item.created_at
      ) order by grant_item.created_at desc, grant_item.id desc)
      from platform.entitlement_grants as grant_item
      join platform.products as product on product.id = grant_item.product_id
      join platform.product_versions as version on version.id = grant_item.product_version_id
      where grant_item.user_id = p_user_id
    ), '[]'::jsonb),
    'redemptions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', redemption.id,
        'batchId', redemption.batch_id,
        'userId', redemption.user_id,
        'productSku', product.sku,
        'status', 'redeemed',
        'redeemedAt', redemption.redeemed_at
      ) order by redemption.redeemed_at desc, redemption.id desc)
      from platform.redemptions as redemption
      join platform.redemption_batches as batch on batch.id = redemption.batch_id
      join platform.products as product on product.id = batch.product_id
      where redemption.user_id = p_user_id
    ), '[]'::jsonb),
    'feedback', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', feedback.id,
        'appSlug', app.slug,
        'kind', feedback.kind,
        'title', feedback.title,
        'content', case when actor_role in ('owner', 'admin', 'support') then feedback.content else null end,
        'status', feedback.status,
        'createdAt', feedback.created_at
      ) order by feedback.created_at desc, feedback.id desc)
      from platform.feedback_requests as feedback
      join platform.platform_apps as app on app.id = feedback.app_id
      where feedback.user_id = p_user_id
    ), '[]'::jsonb),
    'sessionSummary', jsonb_build_object(
      'activeCount', (select count(*)::integer from platform.platform_sessions as session_item where session_item.user_id = p_user_id and session_item.revoked_at is null and session_item.expires_at > timezone('utc', now())),
      'totalCount', (select count(*)::integer from platform.platform_sessions as session_item where session_item.user_id = p_user_id),
      'lastSeenAt', (select max(session_item.last_seen_at) from platform.platform_sessions as session_item where session_item.user_id = p_user_id)
    ),
    'deletionRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', request_item.id,
        'userId', request_item.user_id,
        'status', request_item.status,
        'executeAfter', request_item.execute_after,
        'attemptCount', request_item.attempt_count,
        'lastErrorCode', request_item.last_error_code,
        'nextAttemptAt', request_item.next_attempt_at,
        'requestedAt', request_item.requested_at,
        'completedAt', request_item.completed_at,
        'cancelledAt', request_item.cancelled_at
      ) order by request_item.requested_at desc, request_item.id desc)
      from platform.account_deletion_requests as request_item
      where request_item.user_id = p_user_id
    ), '[]'::jsonb),
    'auditTimeline', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', audit.id,
        'actorType', audit.actor_type,
        'actorId', audit.actor_id,
        'action', audit.action,
        'targetType', audit.target_type,
        'targetId', audit.target_id,
        'requestId', audit.request_id,
        'reason', audit.reason,
        'beforeSummary', audit.before_summary,
        'afterSummary', audit.after_summary,
        'createdAt', audit.created_at
      ) order by audit.created_at desc, audit.id desc)
      from (
        select distinct audit_log.*
          from platform.audit_logs as audit_log
         where audit_log.actor_id = p_user_id
            or audit_log.target_id = p_user_id
            or exists (
              select 1 from platform.entitlement_grants as grant_item
               where grant_item.id = audit_log.target_id and grant_item.user_id = p_user_id
            )
            or exists (
              select 1 from platform.redemptions as redemption
               where redemption.id = audit_log.target_id and redemption.user_id = p_user_id
            )
            or exists (
              select 1 from platform.feedback_requests as feedback
               where feedback.id = audit_log.target_id and feedback.user_id = p_user_id
            )
            or exists (
              select 1 from platform.account_deletion_requests as request_item
               where request_item.id = audit_log.target_id and request_item.user_id = p_user_id
            )
         order by audit_log.created_at desc, audit_log.id desc
         limit 100
      ) as audit
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.admin_query_customer_resource(uuid, text, text, integer, text, text, text, text) is
  'Returns the allowlisted Admin Customer resource projection with opaque cursor pagination.';
comment on function public.admin_user_overview(uuid, uuid) is
  'Returns one role-filtered User 360 aggregate without exposing sessions, tokens, IPs, or database tables.';

revoke all on function public.admin_query_customer_resource(uuid, text, text, integer, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.admin_user_overview(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_query_customer_resource(uuid, text, text, integer, text, text, text, text)
  to service_role;
grant execute on function public.admin_user_overview(uuid, uuid)
  to service_role;
