-- Explicit Admin Product list projection. Products are a Catalog resource but
-- use their own query because the legacy operational projection is intentionally
-- limited to applications, users, entitlements, redemptions, feedback, and audit.

drop function if exists public.admin_query_products(uuid, text, integer, text, text, text, text);

create or replace function public.admin_query_products(
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
  if p_resource <> 'products' then
    raise exception using errcode = '22023', message = 'The Product resource is not supported';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'The Product page size is invalid';
  end if;
  if p_direction not in ('asc', 'desc') then
    raise exception using errcode = '22023', message = 'The Product sort direction is invalid';
  end if;
  if p_search is not null and (length(p_search) < 1 or length(p_search) > 200) then
    raise exception using errcode = '22023', message = 'The Product search value is invalid';
  end if;
  if p_status is not null and length(p_status) > 50 then
    raise exception using errcode = '22023', message = 'The Product status filter is invalid';
  end if;
  if p_sort not in ('createdAt', 'name', 'status') then
    raise exception using errcode = '22023', message = 'The Product sort field is invalid';
  end if;

  if p_cursor is not null then
    begin
      cursor_json := convert_from(decode(p_cursor, 'base64'), 'utf8')::jsonb;
      cursor_value := cursor_json ->> 'value';
      cursor_id := (cursor_json ->> 'id')::uuid;
    exception when others then
      raise exception using errcode = '22023', message = 'The Product cursor is invalid';
    end;
  end if;

  return (
    with base as (
      select product.id,
             product.sku,
             product.name,
             product.billing_type,
             product.status,
             current_version.id as current_version_id,
             current_version.version as current_version,
             product.created_at,
             case p_sort
               when 'name' then product.name
               when 'status' then product.status
               else to_char(product.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
             end as sort_value
        from platform.products as product
        left join platform.product_versions as current_version
          on current_version.id = product.current_version_id
       where (p_search is null or product.sku ilike '%' || p_search || '%' or product.name ilike '%' || p_search || '%')
         and (p_status is null or product.status = p_status)
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
    ), selected as (
      select * from filtered where row_number < p_limit
    ), next_row as (
      select * from filtered where row_number = p_limit limit 1
    )
    select jsonb_build_object(
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id,
        'sku', sku,
        'name', name,
        'billingType', billing_type,
        'status', status,
        'currentVersion', case when current_version_id is null then null else jsonb_build_object(
          'id', current_version_id,
          'version', current_version,
          'status', 'published'
        ) end
      ) order by row_number) from selected), '[]'::jsonb),
      'page', jsonb_build_object(
        'hasMore', exists(select 1 from next_row),
        'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)
      )
    )
  );
end;
$$;

comment on function public.admin_query_products(uuid, text, text, integer, text, text, text, text) is
  'Returns an explicit Admin Product list projection with current-version summaries.';

revoke all on function public.admin_query_products(uuid, text, text, integer, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_query_products(uuid, text, text, integer, text, text, text, text)
  to service_role;
