-- Make authenticated feedback and audit events carry explicit Application context,
-- and reuse the same cleanup boundary for application leave and global deletion.

alter table platform.feedback_requests
  add column membership_id uuid references platform.application_memberships(id) on delete restrict;

create index feedback_requests_membership_created_idx
  on platform.feedback_requests (membership_id, created_at desc)
  where membership_id is not null;

alter table platform.audit_logs
  add column application_id uuid references platform.platform_apps(id) on delete restrict;

create index audit_logs_application_created_idx
  on platform.audit_logs (application_id, created_at desc)
  where application_id is not null;

create or replace function platform.assign_audit_application_context()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  context_value text := nullif(current_setting('app.application_id', true), '');
begin
  if new.application_id is null and context_value is not null then
    new.application_id := context_value::uuid;
  elsif context_value is not null and new.application_id is distinct from context_value::uuid then
    raise exception using errcode = '23514', message = 'Audit Application context does not match the server context';
  end if;
  return new;
end;
$$;

create trigger audit_logs_assign_application_context
before insert on platform.audit_logs
for each row execute function platform.assign_audit_application_context();

create or replace function platform.validate_feedback_membership()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
declare
  membership_row platform.application_memberships%rowtype;
begin
  if new.membership_id is null then
    return new;
  end if;
  if new.user_id is null then
    return new;
  end if;
  select membership.* into membership_row
    from platform.application_memberships as membership
   where membership.id = new.membership_id;
  if not found or membership_row.application_id <> new.app_id
     or membership_row.user_id <> new.user_id or membership_row.status <> 'active' then
    raise exception using errcode = '23514', message = 'Feedback membership does not match the active Application context';
  end if;
  return new;
end;
$$;

create trigger feedback_requests_validate_membership
before insert or update on platform.feedback_requests
for each row execute function platform.validate_feedback_membership();

create or replace function public.create_application_feedback(
  p_application_id uuid,
  p_user_id uuid,
  p_membership_id uuid,
  p_kind text,
  p_title text,
  p_content text
)
returns table (
  id uuid,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
declare
  feedback_id_value uuid := gen_random_uuid();
begin
  if p_application_id is null or p_user_id is null or p_membership_id is null
     or p_kind is null or btrim(p_kind) = ''
     or p_title is null or btrim(p_title) = ''
     or p_content is null or btrim(p_content) = '' then
    raise exception using errcode = '23514', message = 'Feedback fields and Application membership are required';
  end if;
  if not exists (
    select 1 from platform.application_memberships as membership
     where membership.id = p_membership_id
       and membership.application_id = p_application_id
       and membership.user_id = p_user_id
       and membership.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'An active Application membership is required';
  end if;

  insert into platform.feedback_requests
    (id, app_id, user_id, membership_id, kind, title, content)
  values
    (feedback_id_value, p_application_id, p_user_id, p_membership_id,
     btrim(p_kind), btrim(p_title), btrim(p_content));

  return query select feedback_id_value, 'open', now();
end;
$$;

comment on function public.create_application_feedback(uuid, uuid, uuid, text, text, text) is
  'Creates authenticated feedback from the server-resolved Application and Membership context.';

revoke all on function public.create_application_feedback(uuid, uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.create_application_feedback(uuid, uuid, uuid, text, text, text)
  to service_role;

create or replace function platform.cleanup_application_data(p_membership_id uuid)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog, platform
as $$
declare
  membership_row platform.application_memberships%rowtype;
  grant_row record;
  revoked_grant_count integer := 0;
  anonymized_feedback_count integer := 0;
  detached_order_count integer := 0;
begin
  select membership.* into membership_row
    from platform.application_memberships as membership
   where membership.id = p_membership_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The Application membership was not found';
  end if;

  perform set_config('app.application_id', membership_row.application_id::text, true);
  for grant_row in
    select grant_item.id
      from platform.entitlement_grants as grant_item
     where grant_item.user_id = membership_row.user_id
       and grant_item.application_id = membership_row.application_id
       and grant_item.status = 'active'
     order by grant_item.id
     for update
  loop
    perform public.revoke_entitlement(
      grant_row.id, 'system', null, 'Application membership cleanup', null
    );
    revoked_grant_count := revoked_grant_count + 1;
  end loop;

  update platform.feedback_requests
     set user_id = null, title = '[deleted]', content = '[deleted]'
   where app_id = membership_row.application_id
     and user_id = membership_row.user_id;
  get diagnostics anonymized_feedback_count = row_count;

  update platform.orders
     set user_id = null
   where application_id = membership_row.application_id
     and user_id = membership_row.user_id;
  get diagnostics detached_order_count = row_count;

  perform set_config('app.application_id', '', true);
  return jsonb_build_object(
    'membershipId', membership_row.id,
    'revokedGrantCount', revoked_grant_count,
    'anonymizedFeedbackCount', anonymized_feedback_count,
    'detachedOrderCount', detached_order_count
  );
end;
$$;

revoke all on function platform.cleanup_application_data(uuid)
  from public, anon, authenticated, service_role;

-- Keep application membership command audits and leave cleanup in the same transaction.
do $$
declare
  function_definition text;
begin
  select pg_get_functiondef(proc.oid) into function_definition
    from pg_proc as proc
   where proc.oid = 'public.application_membership_command(uuid,text,uuid,uuid,uuid,text,text,text,text,uuid)'::regprocedure;
  function_definition := replace(
    function_definition,
    E'    select membership.* into membership_row\n      from platform.application_memberships as membership\n     where membership.id = p_membership_id;\n  end if;',
    E'    select membership.* into membership_row\n      from platform.application_memberships as membership\n     where membership.id = p_membership_id;\n    if p_action = ''leave'' then\n      perform platform.cleanup_application_data(membership_row.id);\n    end if;\n  end if;'
  );
  function_definition := replace(
    function_definition,
    E'  insert into platform.audit_logs\n',
    E'  if target_application_id is not null then\n    perform set_config(''app.application_id'', target_application_id::text, true);\n  end if;\n\n  insert into platform.audit_logs\n'
  );
  execute function_definition;
end;
$$;

-- Global deletion cleans each Application membership before revoking any remaining
-- global grants and de-identifying global user references.
do $$
declare
  function_definition text;
begin
  select pg_get_functiondef(proc.oid) into function_definition
    from pg_proc as proc
   where proc.oid = 'public.complete_account_deletion_request(uuid,uuid,uuid)'::regprocedure;
  function_definition := replace(function_definition,
    E'  grant_row record;\n',
    E'  grant_row record;\n  membership_row record;\n  cleaned_membership_count integer := 0;\n'
  );
  function_definition := replace(function_definition,
    E'  for grant_row in\n',
    E'  for membership_row in\n    select membership.id from platform.application_memberships as membership\n     where membership.user_id = request_row.user_id\n       and membership.status <> ''deleted''\n     order by membership.id for update\n  loop\n    perform platform.cleanup_application_data(membership_row.id);\n    update platform.application_memberships\n       set status = ''deleted'', deleted_at = coalesce(deleted_at, now_value),\n           left_at = coalesce(left_at, now_value), suspended_at = null, suspended_reason = null\n     where id = membership_row.id;\n    cleaned_membership_count := cleaned_membership_count + 1;\n  end loop;\n\n  for grant_row in\n'
  );
  function_definition := replace(function_definition,
    E'    ''revokedGrantCount'', revoked_grant_count,\n',
    E'    ''revokedGrantCount'', revoked_grant_count,\n    ''cleanedMembershipCount'', cleaned_membership_count,\n'
  );
  execute function_definition;
end;
$$;

revoke all on function platform.assign_audit_application_context() from public, anon, authenticated, service_role;
revoke all on function platform.validate_feedback_membership() from public, anon, authenticated, service_role;

-- Extend the allowlisted Admin projection with an explicit Application filter.
-- The legacy overload remains available for existing internal callers; the API
-- always uses this overload when it needs application-scoped filtering.
do $$
declare
  function_definition text;
begin
  select pg_get_functiondef(proc.oid) into function_definition
    from pg_proc as proc
   where proc.oid = 'public.admin_query_resource(uuid,text,text,integer,text,text,text,text)'::regprocedure;
  function_definition := regexp_replace(
    function_definition,
    E'p_direction text DEFAULT ''desc''::text\\s*\\)',
    E'p_direction text DEFAULT ''desc''::text,\n  p_application_id uuid DEFAULT null\n)'
  );
  function_definition := replace(
    function_definition,
    E'        select feedback.id, app.slug as app_slug, feedback.user_id, feedback.kind, feedback.title,',
    E'        select feedback.id, feedback.app_id as application_id, app.slug as app_slug, feedback.user_id, feedback.kind, feedback.title,'
  );
  function_definition := replace(
    function_definition,
    E'           and (p_status is null or feedback.status = p_status)',
    E'           and (p_status is null or feedback.status = p_status)\n           and (p_application_id is null or feedback.app_id = p_application_id)'
  );
  function_definition := replace(
    function_definition,
    E'''items'', coalesce((select jsonb_agg(jsonb_build_object(''id'', id, ''appSlug'', app_slug,',
    E'''items'', coalesce((select jsonb_agg(jsonb_build_object(''id'', id, ''applicationId'', application_id, ''appSlug'', app_slug,'
  );
  function_definition := replace(
    function_definition,
    E'        select audit.id, audit.actor_type, audit.actor_id, audit.action, audit.target_type, audit.target_id,',
    E'        select audit.id, audit.application_id, audit.actor_type, audit.actor_id, audit.action, audit.target_type, audit.target_id,'
  );
  function_definition := replace(
    function_definition,
    E'         where p_search is null or audit.action ilike ''%'' || p_search || ''%'' or audit.target_type ilike ''%'' || p_search || ''%''',
    E'         where (p_search is null or audit.action ilike ''%'' || p_search || ''%'' or audit.target_type ilike ''%'' || p_search || ''%'')\n           and (p_application_id is null or audit.application_id = p_application_id)'
  );
  function_definition := replace(
    function_definition,
    E'''items'', coalesce((select jsonb_agg(jsonb_build_object(''id'', id, ''actorType'', actor_type,',
    E'''items'', coalesce((select jsonb_agg(jsonb_build_object(''id'', id, ''applicationId'', application_id, ''actorType'', actor_type,'
  );
  execute function_definition;
end;
$$;

drop function public.admin_query_resource(uuid, text, text, integer, text, text, text, text);

comment on function public.admin_query_resource(uuid, text, text, integer, text, text, text, text, uuid) is
  'Returns allowlisted Admin projections with optional explicit Application filtering.';
revoke all on function public.admin_query_resource(uuid, text, text, integer, text, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_query_resource(uuid, text, text, integer, text, text, text, text, uuid)
  to service_role;
