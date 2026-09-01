-- Read-only Admin query projections. Resource names, sort fields, and role redaction
-- are fixed here; callers cannot provide table names or SQL expressions.

create or replace function public.admin_query_resource(
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

  if p_resource not in ('applications', 'users', 'entitlements', 'redemptions', 'feedback', 'audit-logs') then
    raise exception using errcode = '22023', message = 'The Admin resource is not supported';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'The Admin page size is invalid';
  end if;
  if p_direction not in ('asc', 'desc') then
    raise exception using errcode = '22023', message = 'The Admin sort direction is invalid';
  end if;
  if p_search is not null and (length(p_search) < 1 or length(p_search) > 200) then
    raise exception using errcode = '22023', message = 'The Admin search value is invalid';
  end if;

  if p_cursor is not null then
    begin
      cursor_json := convert_from(decode(p_cursor, 'base64'), 'utf8')::jsonb;
      cursor_value := cursor_json ->> 'value';
      cursor_id := (cursor_json ->> 'id')::uuid;
    exception when others then
      raise exception using errcode = '22023', message = 'The Admin cursor is invalid';
    end;
  end if;

  if p_resource = 'applications' then
    if actor_role not in ('owner', 'admin', 'support') then
      raise exception using errcode = '42501', message = 'The Admin role cannot read applications';
    end if;
    if p_sort not in ('createdAt', 'updatedAt', 'name', 'slug', 'status') then
      raise exception using errcode = '22023', message = 'The application sort field is invalid';
    end if;

    return (
      with base as (
        select app.id,
               app.slug,
               app.name,
               app.category,
               app.status,
               count(origin.id)::integer as origin_count,
               app.created_at,
               app.updated_at,
               case p_sort
                 when 'updatedAt' then to_char(app.updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
                 when 'name' then app.name
                 when 'slug' then app.slug
                 when 'status' then app.status
                 else to_char(app.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
               end as sort_value
          from platform.platform_apps as app
          left join platform.app_origins as origin on origin.app_id = app.id and origin.is_active
         where (p_search is null or app.slug ilike '%' || p_search || '%' or app.name ilike '%' || p_search || '%')
           and (p_status is null or app.status = p_status)
         group by app.id
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
          'id', id, 'slug', slug, 'name', name, 'category', category, 'status', status,
          'originCount', origin_count, 'createdAt', created_at, 'updatedAt', updated_at
        ) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object(
          'hasMore', exists(select 1 from next_row),
          'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)
        )
      )
    );
  end if;

  if p_resource = 'users' then
    if p_sort not in ('createdAt', 'displayName', 'status') then
      raise exception using errcode = '22023', message = 'The user sort field is invalid';
    end if;

    return (
      with base as (
        select profile.id,
               case when actor_role = 'finance' then null else profile.display_name end as display_name,
               profile.status,
               member.role as admin_role,
               profile.created_at,
               case p_sort
                 when 'displayName' then coalesce(profile.display_name, '')
                 when 'status' then profile.status
                 else to_char(profile.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
               end as sort_value
          from platform.profiles as profile
          left join platform.admin_members as member on member.user_id = profile.id
         where (p_search is null or profile.display_name ilike '%' || p_search || '%' or profile.id::text ilike '%' || p_search || '%')
           and (p_status is null or profile.status = p_status)
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
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object(
        'items', coalesce((select jsonb_agg(jsonb_build_object(
          'id', id, 'displayName', display_name, 'status', status, 'adminRole', admin_role, 'createdAt', created_at
        ) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row))
      )
    );
  end if;

  if p_resource = 'entitlements' then
    if p_sort not in ('createdAt', 'status') then
      raise exception using errcode = '22023', message = 'The entitlement sort field is invalid';
    end if;

    return (
      with base as (
        select grant_item.id,
               grant_item.user_id,
               case when actor_role = 'finance' then null else profile.display_name end as display_name,
               product.sku as product_sku,
               version.version as product_version,
               grant_item.source_type,
               grant_item.status,
               grant_item.starts_at,
               grant_item.expires_at,
               grant_item.created_at,
               case p_sort when 'status' then grant_item.status else to_char(grant_item.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.entitlement_grants as grant_item
          join platform.products as product on product.id = grant_item.product_id
          join platform.product_versions as version on version.id = grant_item.product_version_id
          join platform.profiles as profile on profile.id = grant_item.user_id
         where (p_search is null or product.sku ilike '%' || p_search || '%' or grant_item.user_id::text ilike '%' || p_search || '%')
           and (p_status is null or grant_item.status = p_status)
      ), filtered as (
        select row_number() over (
                 order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
                   case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc
               ) - 1 as row_number, base.* from base
         where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id))) or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object(
        'items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'userId', user_id, 'displayName', display_name, 'productSku', product_sku, 'productVersion', product_version, 'sourceType', source_type, 'status', status, 'startsAt', starts_at, 'expiresAt', expires_at, 'createdAt', created_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row))
      )
    );
  end if;

  if p_resource = 'redemptions' then
    if p_sort not in ('redeemedAt', 'status') then
      raise exception using errcode = '22023', message = 'The redemption sort field is invalid';
    end if;

    return (
      with base as (
        select redemption.id, redemption.batch_id, redemption.user_id, product.sku as product_sku,
               'redeemed'::text as status, redemption.redeemed_at,
               case p_sort when 'status' then 'redeemed' else to_char(redemption.redeemed_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.redemptions as redemption
          join platform.redemption_batches as batch on batch.id = redemption.batch_id
          join platform.products as product on product.id = batch.product_id
         where p_search is null or product.sku ilike '%' || p_search || '%' or redemption.user_id::text ilike '%' || p_search || '%'
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc, case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.* from base
         where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id))) or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object(
        'items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'batchId', batch_id, 'userId', user_id, 'productSku', product_sku, 'status', status, 'redeemedAt', redeemed_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row))
      )
    );
  end if;

  if p_resource = 'feedback' then
    if p_sort not in ('createdAt', 'status', 'title') then
      raise exception using errcode = '22023', message = 'The feedback sort field is invalid';
    end if;

    return (
      with base as (
        select feedback.id, app.slug as app_slug, feedback.user_id, feedback.kind, feedback.title,
               case when actor_role in ('owner', 'admin', 'support') then feedback.content else null end as content,
               feedback.status, feedback.created_at,
               case p_sort when 'status' then feedback.status when 'title' then feedback.title else to_char(feedback.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.feedback_requests as feedback
          join platform.platform_apps as app on app.id = feedback.app_id
         where (p_search is null or feedback.title ilike '%' || p_search || '%' or feedback.kind ilike '%' || p_search || '%')
           and (p_status is null or feedback.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc, case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.* from base
         where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id))) or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object(
        'items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'appSlug', app_slug, 'userId', user_id, 'kind', kind, 'title', title, 'content', content, 'status', status, 'createdAt', created_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row))
      )
    );
  end if;

  if p_resource = 'audit-logs' then
    if p_sort not in ('createdAt', 'action', 'targetType') then
      raise exception using errcode = '22023', message = 'The audit sort field is invalid';
    end if;

    return (
      with base as (
        select audit.id, audit.actor_type, audit.actor_id, audit.action, audit.target_type, audit.target_id,
               audit.request_id, audit.reason, audit.before_summary, audit.after_summary, audit.created_at,
               case p_sort when 'action' then audit.action when 'targetType' then audit.target_type else to_char(audit.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.audit_logs as audit
         where p_search is null or audit.action ilike '%' || p_search || '%' or audit.target_type ilike '%' || p_search || '%'
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc, case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.* from base
         where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id))) or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object(
        'items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'actorType', actor_type, 'actorId', actor_id, 'action', action, 'targetType', target_type, 'targetId', target_id, 'requestId', request_id, 'reason', reason, 'beforeSummary', before_summary, 'afterSummary', after_summary, 'createdAt', created_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row))
      )
    );
  end if;

  raise exception using errcode = '22023', message = 'The Admin resource is not supported';
end;
$$;

comment on function public.admin_query_resource(uuid, text, text, integer, text, text, text, text) is
  'Returns allowlisted Admin resource projections with role redaction and opaque cursor pagination.';

revoke all on function public.admin_query_resource(uuid, text, text, integer, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_query_resource(uuid, text, text, integer, text, text, text, text)
  to service_role;
