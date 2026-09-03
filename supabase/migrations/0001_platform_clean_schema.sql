


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "platform";


ALTER SCHEMA "platform" OWNER TO "postgres";


COMMENT ON SCHEMA "platform" IS 'Private platform schema. Access is provided through controlled backend functions.';



CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "platform"."application_owns_product_version"("p_application_id" "uuid", "p_product_version_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
  select p_application_id is not null
     and p_product_version_id is not null
     and exists (
       select 1
         from platform.product_version_features as snapshot
         join platform.features as feature on feature.id = snapshot.feature_id
        where snapshot.product_version_id = p_product_version_id
          and (feature.app_id is null or feature.app_id = p_application_id)
     );
$$;


ALTER FUNCTION "platform"."application_owns_product_version"("p_application_id" "uuid", "p_product_version_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."assign_application_context_to_entitlement"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  context_value text := nullif(current_setting('app.application_id', true), '');
begin
  if new.application_id is null and context_value is not null then
    new.application_id := context_value::uuid;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."assign_application_context_to_entitlement"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."assign_application_context_to_redemption"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  context_value text := nullif(current_setting('app.application_id', true), '');
begin
  if new.application_id is null and context_value is not null then
    new.application_id := context_value::uuid;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."assign_application_context_to_redemption"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."assign_audit_application_context"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "platform"."assign_audit_application_context"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."cleanup_application_data"("p_membership_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "platform"."cleanup_application_data"("p_membership_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."handle_new_auth_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  insert into platform.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;


ALTER FUNCTION "platform"."handle_new_auth_user"() OWNER TO "postgres";


COMMENT ON FUNCTION "platform"."handle_new_auth_user"() IS 'Controlled Auth-to-profile lifecycle hook; creates the platform profile after an Auth user is inserted.';



CREATE OR REPLACE FUNCTION "platform"."payment_event_summary_is_safe"("value" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  key_name text;
  child jsonb;
begin
  if jsonb_typeof(value) = 'object' then
    for key_name, child in
      select entry.key_name, entry.child
        from jsonb_each(value) as entry(key_name, child)
    loop
      if lower(key_name) in (
        'authorization', 'card_number', 'card_expiry', 'cvv', 'cvc', 'pan',
        'password', 'secret', 'token', 'access_token', 'refresh_token',
        'payment_method', 'payment_method_token', 'credential', 'credentials'
      ) then
        return false;
      end if;
      if not platform.payment_event_summary_is_safe(child) then
        return false;
      end if;
    end loop;
  elsif jsonb_typeof(value) = 'array' then
    for child in
      select entry.child
        from jsonb_array_elements(value) as entry(child)
    loop
      if not platform.payment_event_summary_is_safe(child) then
        return false;
      end if;
    end loop;
  end if;
  return true;
end;
$$;


ALTER FUNCTION "platform"."payment_event_summary_is_safe"("value" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_admin_member_identity_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if new.user_id is distinct from old.user_id then
    raise exception using
      errcode = '23514',
      message = 'Admin membership identity cannot change';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_admin_member_identity_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_application_membership_identity_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if new.id <> old.id
     or new.application_id is distinct from old.application_id
     or new.user_id is distinct from old.user_id
     or new.created_source is distinct from old.created_source
     or new.created_by is distinct from old.created_by
     or new.joined_at is distinct from old.joined_at then
    raise exception using
      errcode = '23514',
      message = 'Application membership identity fields cannot change';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_application_membership_identity_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_application_oauth_client_identity_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if new.id <> old.id
     or new.application_id is distinct from old.application_id
     or new.provider is distinct from old.provider
     or new.external_client_id is distinct from old.external_client_id
     or new.client_type is distinct from old.client_type
     or new.environment is distinct from old.environment then
    raise exception using
      errcode = '23514',
      message = 'OAuth Client Binding identity fields cannot change';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_application_oauth_client_identity_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_audit_log_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if tg_op = 'UPDATE'
     and current_setting('app.audit_scrub', true) in ('account_deletion', 'retention_cleanup')
     and old.ip_hash is not null
     and new.ip_hash is null
     and new.id is not distinct from old.id
     and new.actor_type is not distinct from old.actor_type
     and new.actor_id is not distinct from old.actor_id
     and new.action is not distinct from old.action
     and new.target_type is not distinct from old.target_type
     and new.target_id is not distinct from old.target_id
     and new.request_id is not distinct from old.request_id
     and new.reason is not distinct from old.reason
     and new.before_summary is not distinct from old.before_summary
     and new.after_summary is not distinct from old.after_summary
     and new.created_at is not distinct from old.created_at then
    return new;
  end if;

  raise exception using
    errcode = '23514',
    message = 'Audit logs are append-only';
end;
$$;


ALTER FUNCTION "platform"."prevent_audit_log_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_current_retired_version"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if new.status <> 'published'
     and exists (
       select 1
       from platform.products
       where id = new.product_id
         and current_version_id = new.id
     ) then
    raise exception using
      errcode = '23514',
      message = 'The current product version must remain published';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_current_retired_version"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_entitlement_application_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if old.application_id is not null and new.application_id is distinct from old.application_id then
    raise exception using
      errcode = '23514',
      message = 'Entitlement application context is immutable';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_entitlement_application_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_entitlement_grant_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '23514',
      message = 'Entitlement grant history cannot be deleted';
  end if;

  if new.id is distinct from old.id
     or new.user_id is distinct from old.user_id
     or new.product_id is distinct from old.product_id
     or new.product_version_id is distinct from old.product_version_id
     or new.resolution_mode is distinct from old.resolution_mode
     or new.source_type is distinct from old.source_type
     or new.source_id is distinct from old.source_id
     or new.starts_at is distinct from old.starts_at
     or new.expires_at is distinct from old.expires_at
     or new.restores_grant_id is distinct from old.restores_grant_id
     or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '23514',
      message = 'Entitlement grant identity and terms are immutable';
  end if;

  if old.status = 'revoked' then
    raise exception using
      errcode = '23514',
      message = 'Revoked entitlement grants cannot be changed';
  end if;

  if new.status <> 'revoked' then
    raise exception using
      errcode = '23514',
      message = 'Entitlement grants only transition from active to revoked';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_entitlement_grant_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_origin_identity_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if new.app_id is distinct from old.app_id
     or new.environment is distinct from old.environment
     or new.origin is distinct from old.origin then
    raise exception using
      errcode = '23514',
      message = 'application Origin identity cannot change; deactivate it and create a new exact Origin';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_origin_identity_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_product_version_feature_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  version_status text;
begin
  if tg_op = 'DELETE' then
    select version.status
      into version_status
      from platform.product_versions as version
     where version.id = old.product_version_id;
    if version_status in ('published', 'retired') then
      raise exception using
        errcode = '23514',
        message = 'Published product version feature snapshots cannot be deleted';
    end if;
    return old;
  end if;

  if new.product_version_id is distinct from old.product_version_id
     or new.feature_id is distinct from old.feature_id then
    raise exception using
      errcode = '23514',
      message = 'Product version feature identity cannot change';
  end if;

  select version.status
    into version_status
    from platform.product_versions as version
   where version.id = old.product_version_id;
  if version_status in ('published', 'retired') then
    raise exception using
      errcode = '23514',
      message = 'Published product version feature snapshots are immutable';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_product_version_feature_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_product_version_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  catalog_command text := current_setting('app.catalog_command', true);
begin
  if tg_op = 'DELETE' then
    if old.status in ('published', 'retired') then
      raise exception using
        errcode = '23514',
        message = 'Published product versions cannot be deleted';
    end if;
    return old;
  end if;

  if old.status = 'retired' then
    raise exception using
      errcode = '23514',
      message = 'Retired product versions cannot be changed';
  end if;

  if old.status = 'published' then
    if catalog_command = 'retire'
       and new.status = 'retired'
       and new.product_id = old.product_id
       and new.version = old.version
       and new.access_duration_days is not distinct from old.access_duration_days
       and new.sales_terms is not distinct from old.sales_terms
       and new.published_at is not distinct from old.published_at
       and new.created_at is not distinct from old.created_at then
      return new;
    end if;

    raise exception using
      errcode = '23514',
      message = 'Published product versions are immutable; create a new version';
  end if;

  if new.status in ('published', 'retired')
     and old.status = 'draft'
     and coalesce(catalog_command, '') <> 'publish' then
    raise exception using
      errcode = '23514',
      message = 'Product version publication requires a controlled command';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_product_version_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_profile_identity_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if new.id <> old.id then
    raise exception 'profile identity is immutable'
      using errcode = '23514';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_profile_identity_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_redemption_application_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if old.application_id is not null and new.application_id is distinct from old.application_id then
    raise exception using
      errcode = '23514',
      message = 'Redemption application context is immutable';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_redemption_application_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_redemption_code_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '23514',
      message = 'Redemption code history cannot be deleted';
  end if;

  if new.id is distinct from old.id
     or new.batch_id is distinct from old.batch_id
     or new.code_hash is distinct from old.code_hash
     or new.code_hint is distinct from old.code_hint
     or new.pepper_version is distinct from old.pepper_version
     or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '23514',
      message = 'Redemption code identity is immutable';
  end if;

  if old.status <> 'issued' then
    raise exception using
      errcode = '23514',
      message = 'Redeemed or revoked codes cannot be changed';
  end if;

  if new.status not in ('redeemed', 'revoked') then
    raise exception using
      errcode = '23514',
      message = 'Redemption codes only transition from issued';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_redemption_code_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_redemption_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if tg_op = 'UPDATE'
     and current_setting('app.retention_cleanup', true) = 'retention_cleanup'
     and old.ip_hash is not null
     and new.ip_hash is null
     and new.id is not distinct from old.id
     and new.code_id is not distinct from old.code_id
     and new.batch_id is not distinct from old.batch_id
     and new.user_id is not distinct from old.user_id
     and new.grant_id is not distinct from old.grant_id
     and new.idempotency_record_id is not distinct from old.idempotency_record_id
     and new.redeemed_at is not distinct from old.redeemed_at then
    return new;
  end if;

  raise exception using
    errcode = '23514',
    message = 'Redemption receipts are immutable';
end;
$$;


ALTER FUNCTION "platform"."prevent_redemption_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."prevent_referenced_app_slug_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if new.slug is distinct from old.slug
     and (
       exists (select 1 from platform.app_origins where app_id = old.id)
       or exists (select 1 from platform.application_oauth_clients where application_id = old.id)
     ) then
    raise exception using
      errcode = '23514',
      message = 'application slug cannot change after the application is externally referenced';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."prevent_referenced_app_slug_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;


ALTER FUNCTION "platform"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_application_scoped_entitlement"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
begin
  if new.application_id is not null
     and not platform.application_owns_product_version(new.application_id, new.product_version_id) then
    raise exception using
      errcode = '23514',
      message = 'Entitlement application does not own the product version feature';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."validate_application_scoped_entitlement"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_application_scoped_order_item"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  order_application_id uuid;
begin
  select order_fact.application_id into order_application_id
    from platform.orders as order_fact
   where order_fact.id = new.order_id;
  if order_application_id is not null
     and not platform.application_owns_product_version(order_application_id, new.product_version_id) then
    raise exception using
      errcode = '23514',
      message = 'Order application does not own the product version feature';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."validate_application_scoped_order_item"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_entitlement_restore_link"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  original_grant record;
begin
  if new.restores_grant_id is null then
    return new;
  end if;

  select grant_row.id,
         grant_row.user_id,
         grant_row.product_id,
         grant_row.product_version_id,
         grant_row.status,
         grant_row.restores_grant_id
    into original_grant
    from platform.entitlement_grants as grant_row
   where grant_row.id = new.restores_grant_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Restored entitlement must reference an existing grant';
  end if;

  if original_grant.status <> 'revoked'
     or original_grant.restores_grant_id is not null
     or original_grant.user_id <> new.user_id
     or original_grant.product_id <> new.product_id
     or original_grant.product_version_id <> new.product_version_id then
    raise exception using
      errcode = '23514',
      message = 'Admin restore must point to a matching original revoked grant';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "platform"."validate_entitlement_restore_link"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_feedback_membership"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "platform"."validate_feedback_membership"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_order_item_snapshot"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  order_row platform.orders%rowtype;
  product_row platform.products%rowtype;
  version_row platform.product_versions%rowtype;
  price_row platform.product_prices%rowtype;
  now_value timestamptz := timezone('utc', now());
begin
  if tg_op = 'DELETE' then
    select * into order_row from platform.orders where id = old.order_id;
    if order_row.status is distinct from 'pending' then
      raise exception using errcode = '23514', message = 'Paid order items cannot be deleted';
    end if;
    return old;
  end if;

  select * into order_row from platform.orders where id = new.order_id;
  if not found then
    raise exception using errcode = '23503', message = 'Order item must reference an existing order';
  end if;

  if tg_op = 'UPDATE' and order_row.status is distinct from 'pending' then
    if new.order_id is distinct from old.order_id
       or new.product_id is distinct from old.product_id
       or new.product_version_id is distinct from old.product_version_id
       or new.product_price_id is distinct from old.product_price_id
       or new.quantity is distinct from old.quantity
       or new.unit_amount is distinct from old.unit_amount
       or new.total_amount is distinct from old.total_amount
       or new.product_name is distinct from old.product_name
       or new.sku_snapshot is distinct from old.sku_snapshot
       or new.sales_terms is distinct from old.sales_terms then
      raise exception using errcode = '23514', message = 'Paid order item purchase snapshots are immutable';
    end if;
  end if;

  select * into product_row from platform.products where id = new.product_id;
  if not found then
    raise exception using errcode = '23503', message = 'Order item product was not found';
  end if;

  select * into version_row
    from platform.product_versions
   where id = new.product_version_id
     and product_id = new.product_id;
  if not found or version_row.status <> 'published' then
    raise exception using errcode = '23514', message = 'Order item must reference a published product version';
  end if;
  if new.product_name <> product_row.name or new.sku_snapshot <> product_row.sku
     or new.sales_terms is distinct from version_row.sales_terms then
    raise exception using errcode = '23514', message = 'Order item purchase snapshots do not match the catalog';
  end if;

  if new.product_price_id is not null then
    select * into price_row from platform.product_prices where id = new.product_price_id;
    if not found or price_row.product_version_id <> new.product_version_id then
      raise exception using errcode = '23514', message = 'Order item price must belong to its product version';
    end if;
    if price_row.status <> 'active'
       or price_row.valid_from > now_value
       or (price_row.valid_until is not null and price_row.valid_until <= now_value) then
      raise exception using errcode = '23514', message = 'Order item price is not active';
    end if;
    if order_row.currency <> price_row.currency or new.unit_amount <> price_row.amount_minor then
      raise exception using errcode = '23514', message = 'Order item price and currency do not match the order';
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "platform"."validate_order_item_snapshot"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_order_total"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  order_row platform.orders%rowtype;
  item_total bigint;
  order_id_value uuid;
begin
  if tg_table_name = 'orders' then
    order_id_value := (to_jsonb(new) ->> 'id')::uuid;
  else
    order_id_value := coalesce(
      (to_jsonb(new) ->> 'order_id')::uuid,
      (to_jsonb(old) ->> 'order_id')::uuid
    );
  end if;
  select * into order_row from platform.orders where id = order_id_value;
  if not found or order_row.status = 'pending' then
    return coalesce(new, old);
  end if;

  select coalesce(sum(item.total_amount), 0)
    into item_total
    from platform.order_items as item
   where item.order_id = order_row.id;
  if item_total <> order_row.amount_total then
    raise exception using errcode = '23514', message = 'Order total must equal the sum of order items';
  end if;
  return coalesce(new, old);
end;
$$;


ALTER FUNCTION "platform"."validate_order_total"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_payment_consistency"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  order_row platform.orders%rowtype;
begin
  select * into order_row from platform.orders where id = new.order_id;
  if not found then
    raise exception using errcode = '23503', message = 'Payment must reference an existing order';
  end if;

  if new.currency <> order_row.currency or new.amount <> order_row.amount_total then
    raise exception using errcode = '23514', message = 'Payment amount and currency must match the order';
  end if;

  if tg_op = 'UPDATE'
     and (new.id is distinct from old.id
       or new.order_id is distinct from old.order_id
       or new.provider is distinct from old.provider
       or new.external_payment_id is distinct from old.external_payment_id
       or new.currency is distinct from old.currency
       or new.amount is distinct from old.amount
       or new.created_at is distinct from old.created_at) then
    raise exception using errcode = '23514', message = 'Payment identity is immutable';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."validate_payment_consistency"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_payment_event_consistency"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  payment_row platform.payments%rowtype;
begin
  select * into payment_row from platform.payments where id = new.payment_id;
  if not found then
    raise exception using errcode = '23503', message = 'Payment event must reference an existing payment';
  end if;

  if payment_row.order_id <> new.order_id
     or payment_row.provider <> new.provider
     or payment_row.currency <> new.currency
     or payment_row.amount <> new.amount then
    raise exception using errcode = '23514', message = 'Payment event must match its payment and order';
  end if;

  if not platform.payment_event_summary_is_safe(new.payload_summary) then
    raise exception using errcode = '23514', message = 'Payment event summary contains prohibited credentials';
  end if;

  if tg_op = 'UPDATE'
     and (new.id is distinct from old.id
       or new.payment_id is distinct from old.payment_id
       or new.order_id is distinct from old.order_id
       or new.provider is distinct from old.provider
       or new.external_event_id is distinct from old.external_event_id
       or new.event_type is distinct from old.event_type
       or new.currency is distinct from old.currency
       or new.amount is distinct from old.amount
       or new.occurred_at is distinct from old.occurred_at
       or new.created_at is distinct from old.created_at) then
    raise exception using errcode = '23514', message = 'Payment event identity is immutable';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."validate_payment_event_consistency"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_product_current_version"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  selected_version record;
  catalog_command text := current_setting('app.catalog_command', true);
begin
  if tg_op = 'INSERT'
     and new.current_version_id is not null
     and coalesce(catalog_command, '') <> 'set_current' then
    raise exception using
      errcode = '42501',
      message = 'Current product version changes require a controlled command';
  end if;

  if tg_op = 'UPDATE'
     and new.current_version_id is distinct from old.current_version_id
     and coalesce(catalog_command, '') <> 'set_current' then
    raise exception using
      errcode = '42501',
      message = 'Current product version changes require a controlled command';
  end if;

  if new.current_version_id is not null then
    select version.id, version.product_id, version.status
      into selected_version
      from platform.product_versions as version
     where version.id = new.current_version_id;

    if not found or selected_version.product_id <> new.id then
      raise exception using
        errcode = '23514',
        message = 'Current product version must belong to the product';
    end if;

    if selected_version.status <> 'published' then
      raise exception using
        errcode = '23514',
        message = 'Current product version must be published';
    end if;
  end if;

  if new.status = 'active' and new.current_version_id is null then
    raise exception using
      errcode = '23514',
      message = 'Active products must have a current published version';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "platform"."validate_product_current_version"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_product_price_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  version_status text;
begin
  if new.status = 'active' then
    select version.status
      into version_status
      from platform.product_versions as version
     where version.id = new.product_version_id;

    if not found or version_status <> 'published' then
      raise exception using
        errcode = '23514',
        message = 'Active prices must reference a published product version';
    end if;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "platform"."validate_product_price_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_product_version_feature_value"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  feature_type text;
begin
  select feature.value_type
    into feature_type
    from platform.features as feature
   where feature.id = new.feature_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Product version feature must reference an existing feature';
  end if;

  if feature_type = 'boolean' and jsonb_typeof(new.value) <> 'boolean' then
    raise exception using
      errcode = '23514',
      message = 'Boolean feature values must be JSON booleans';
  elsif feature_type = 'integer' then
    if jsonb_typeof(new.value) <> 'number' then
      raise exception using
        errcode = '23514',
        message = 'Integer feature values must be whole JSON numbers';
    elsif (new.value #>> '{}')::numeric <> trunc((new.value #>> '{}')::numeric) then
      raise exception using
        errcode = '23514',
        message = 'Integer feature values must be whole JSON numbers';
    end if;
  elsif feature_type = 'string' and jsonb_typeof(new.value) <> 'string' then
    raise exception using
      errcode = '23514',
      message = 'String feature values must be JSON strings';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "platform"."validate_product_version_feature_value"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "platform"."validate_redemption_consistency"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  code_row record;
  batch_row record;
  grant_row record;
begin
  select code.batch_id, code.status
    into code_row
    from platform.redemption_codes as code
   where code.id = new.code_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Redemption must reference an existing code';
  end if;

  if code_row.status = 'revoked' then
    raise exception using
      errcode = '23514',
      message = 'Revoked redemption codes cannot be redeemed';
  end if;

  if code_row.batch_id <> new.batch_id then
    raise exception using
      errcode = '23514',
      message = 'Redemption code and batch must match';
  end if;

  select batch.product_id, batch.product_version_id
    into batch_row
    from platform.redemption_batches as batch
   where batch.id = new.batch_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Redemption must reference an existing batch';
  end if;

  select grant_item.user_id,
         grant_item.product_id,
         grant_item.product_version_id,
         grant_item.source_type,
         grant_item.source_id
    into grant_row
    from platform.entitlement_grants as grant_item
   where grant_item.id = new.grant_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Redemption must reference an existing entitlement grant';
  end if;

  if grant_row.user_id <> new.user_id
     or grant_row.product_id <> batch_row.product_id
     or grant_row.product_version_id <> batch_row.product_version_id
     or grant_row.source_type <> 'redemption'
     or grant_row.source_id <> new.id then
    raise exception using
      errcode = '23514',
      message = 'Redemption code, user, batch, and grant must describe one redemption';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "platform"."validate_redemption_consistency"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_application_membership_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid" DEFAULT NULL::"uuid", "p_user_id" "uuid" DEFAULT NULL::"uuid", "p_membership_id" "uuid" DEFAULT NULL::"uuid", "p_reason" "text" DEFAULT NULL::"text", "p_idempotency_key" "text" DEFAULT NULL::"text", "p_request_hash" "text" DEFAULT NULL::"text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  actor_role text;
  membership_application_id uuid;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'Application membership commands require an owner or administrator';
  end if;
  if p_action not in ('create', 'suspend', 'restore', 'delete') then
    raise exception using errcode = '22023', message = 'The Application membership command is not supported';
  end if;
  if p_action = 'create' then
    if p_application_id is null or p_user_id is null or p_membership_id is not null then
      raise exception using errcode = '22023', message = 'Membership creation fields are invalid';
    end if;
  else
    if p_membership_id is null or p_application_id is null then
      raise exception using errcode = '22023', message = 'Membership target fields are required';
    end if;
    select membership.application_id into membership_application_id
      from platform.application_memberships as membership
     where membership.id = p_membership_id;
    if membership_application_id is null then
      raise exception using errcode = 'P0002', message = 'The Application membership was not found';
    end if;
    if membership_application_id <> p_application_id then
      raise exception using errcode = '42501', message = 'The membership does not belong to the requested Application';
    end if;
  end if;

  return public.application_membership_command(
    p_actor_id,
    p_action,
    p_application_id,
    p_user_id,
    p_membership_id,
    'admin',
    p_reason,
    p_idempotency_key,
    p_request_hash,
    p_request_id
  );
end;
$$;


ALTER FUNCTION "public"."admin_application_membership_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_application_membership_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") IS 'Executes owner/admin-only application membership lifecycle commands through the audited domain command.';



CREATE OR REPLACE FUNCTION "public"."admin_catalog_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb" DEFAULT '{}'::"jsonb", "p_reason" "text" DEFAULT NULL::"text", "p_idempotency_key" "text" DEFAULT NULL::"text", "p_request_hash" "text" DEFAULT NULL::"text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $_$
declare
  actor_role text;
  idempotency_row platform.idempotency_records%rowtype;
  version_row platform.product_versions%rowtype;
  product_row platform.products%rowtype;
  origin_row platform.app_origins%rowtype;
  selected_origin platform.app_origins%rowtype;
  app_row platform.platform_apps%rowtype;
  target_id uuid;
  target_type text;
  before_summary jsonb := '{}'::jsonb;
  after_summary jsonb;
  result jsonb;
  command_status text;
  command_published_at timestamptz;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'Catalog commands require an active catalog administrator';
  end if;

  if p_action not in ('publish_product_version', 'retire_product_version',
                      'set_current_product_version', 'change_production_origin') then
    raise exception using errcode = '22023', message = 'The Catalog command is not supported';
  end if;
  if p_resource_id is null or p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'The Catalog command target or payload is invalid';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A Catalog command reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.catalog.command', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.catalog.command'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body;
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The Catalog command is already in progress';
    end if;
  end if;

  if p_action = 'publish_product_version' then
    if p_payload <> '{}'::jsonb then
      raise exception using errcode = '22023', message = 'Publish does not accept additional fields';
    end if;
    select version.*
      into version_row
      from platform.product_versions as version
     where version.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product Version was not found';
    end if;
    before_summary := jsonb_build_object('id', version_row.id, 'status', version_row.status,
      'publishedAt', version_row.published_at);
    select published.product_version_id, published.status, published.published_at
      into target_id, command_status, command_published_at
      from public.publish_product_version(p_resource_id) as published;
    target_type := 'product_version';
    result := jsonb_build_object('productVersionId', target_id, 'status', command_status,
      'publishedAt', command_published_at);
    after_summary := jsonb_build_object('id', target_id, 'status', command_status,
      'publishedAt', command_published_at);
  elsif p_action = 'retire_product_version' then
    if p_payload <> '{}'::jsonb then
      raise exception using errcode = '22023', message = 'Retire does not accept additional fields';
    end if;
    select version.*
      into version_row
      from platform.product_versions as version
     where version.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product Version was not found';
    end if;
    before_summary := jsonb_build_object('id', version_row.id, 'status', version_row.status);
    select retired.product_version_id, retired.status
      into target_id, command_status
      from public.retire_product_version(p_resource_id) as retired;
    target_type := 'product_version';
    result := jsonb_build_object('productVersionId', target_id, 'status', command_status,
      'publishedAt', null);
    after_summary := jsonb_build_object('id', target_id, 'status', command_status);
  elsif p_action = 'set_current_product_version' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key where key <> 'productVersionId')
       or p_payload->>'productVersionId' is null then
      raise exception using errcode = '22023', message = 'Set-current requires only productVersionId';
    end if;
    select product.*
      into product_row
      from platform.products as product
     where product.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product was not found';
    end if;
    select version.*
      into version_row
      from platform.product_versions as version
     where version.id = (p_payload->>'productVersionId')::uuid
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product Version was not found';
    end if;
    before_summary := jsonb_build_object('id', product_row.id, 'currentVersionId', product_row.current_version_id);
    select current_product.product_id, current_product.current_version_id
      into target_id, version_row.id
      from public.set_current_product_version(p_resource_id, (p_payload->>'productVersionId')::uuid)
        as current_product;
    target_type := 'product';
    result := jsonb_build_object('productId', target_id, 'currentVersionId', version_row.id);
    after_summary := jsonb_build_object('id', target_id, 'currentVersionId', version_row.id);
  elsif p_action = 'change_production_origin' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('origin', 'appSlug'))
       or p_payload->>'origin' is null or p_payload->>'appSlug' is null
       or p_payload->>'origin' !~ '^https?://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?$'
       or p_payload->>'appSlug' !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
      raise exception using errcode = '22023', message = 'The production Origin command fields are invalid';
    end if;
    select origin.*
      into origin_row
      from platform.app_origins as origin
     where origin.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The application Origin was not found';
    end if;
    select app.*
      into app_row
      from platform.platform_apps as app
     where app.id = origin_row.app_id
     for update;
    if not found or app_row.slug <> p_payload->>'appSlug' then
      raise exception using errcode = '22023', message = 'The App Slug does not match the application Origin';
    end if;
    before_summary := jsonb_build_object('applicationId', app_row.id, 'appSlug', app_row.slug,
      'previousProductionOrigin', (select jsonb_agg(jsonb_build_object('id', id, 'origin', origin))
        from platform.app_origins where app_id = app_row.id and environment = 'production' and is_active));
    select existing.*
      into selected_origin
      from platform.app_origins as existing
     where existing.app_id = app_row.id
       and existing.environment = 'production'
       and existing.origin = lower(p_payload->>'origin')
     for update;
    if not found then
      insert into platform.app_origins (app_id, environment, origin, is_active)
      values (app_row.id, 'production', lower(p_payload->>'origin'), true)
      returning * into selected_origin;
    end if;
    update platform.app_origins
       set is_active = (id = selected_origin.id)
     where app_id = app_row.id
       and environment = 'production';
    select origin.*
      into selected_origin
      from platform.app_origins as origin
     where origin.id = selected_origin.id;
    target_id := selected_origin.id;
    target_type := 'app_origin';
    result := jsonb_build_object('originId', selected_origin.id, 'applicationId', selected_origin.app_id,
      'appSlug', app_row.slug, 'environment', selected_origin.environment, 'origin', selected_origin.origin,
      'isActive', selected_origin.is_active, 'createdAt', selected_origin.created_at, 'updatedAt', selected_origin.updated_at);
    after_summary := jsonb_build_object('id', selected_origin.id, 'applicationId', selected_origin.app_id,
      'environment', selected_origin.environment, 'origin', selected_origin.origin, 'isActive', selected_origin.is_active);
  end if;

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('admin', p_actor_id, 'catalog.' || p_action, target_type, target_id, p_request_id, p_reason,
     before_summary, coalesce(after_summary, '{}'::jsonb))
  returning id into command_status;

  result := result || jsonb_build_object('auditLogId', command_status::uuid);
  update platform.idempotency_records
     set status = 'completed', resource_type = target_type, resource_id = target_id,
         response_status = 200, response_body = result
   where id = idempotency_row.id;
  return result;
end;
$_$;


ALTER FUNCTION "public"."admin_catalog_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_catalog_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") IS 'Executes explicit, audited high-risk Catalog commands with domain state functions and idempotent retries.';



CREATE OR REPLACE FUNCTION "public"."admin_catalog_draft_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid" DEFAULT NULL::"uuid", "p_parent_id" "uuid" DEFAULT NULL::"uuid", "p_payload" "jsonb" DEFAULT '{}'::"jsonb", "p_expected_updated_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_reason" "text" DEFAULT NULL::"text", "p_idempotency_key" "text" DEFAULT NULL::"text", "p_request_hash" "text" DEFAULT NULL::"text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $_$
declare
  actor_role text;
  idempotency_row platform.idempotency_records%rowtype;
  target_id uuid;
  target_type text;
  before_summary jsonb := '{}'::jsonb;
  after_summary jsonb;
  result jsonb;
  status_code integer := 200;
  app_row platform.platform_apps%rowtype;
  origin_row platform.app_origins%rowtype;
  feature_row platform.features%rowtype;
  product_row platform.products%rowtype;
  version_row platform.product_versions%rowtype;
  price_row platform.product_prices%rowtype;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'Catalog draft editing requires an active catalog administrator';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'The draft payload must be an object';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A draft change reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.catalog.draft', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.catalog.draft'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body;
    end if;
  end if;

  if p_action = 'create_application' then
    if p_resource_id is not null or p_parent_id is not null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('slug', 'name', 'category', 'metadata')) then
      raise exception using errcode = '22023', message = 'The application draft fields are invalid';
    end if;
    if p_payload->>'slug' is null or p_payload->>'slug' !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
       or btrim(coalesce(p_payload->>'name', '')) = ''
       or btrim(coalesce(p_payload->>'category', '')) = '' then
      raise exception using errcode = '22023', message = 'The application draft fields are invalid';
    end if;
    if p_payload ? 'metadata' and jsonb_typeof(p_payload->'metadata') <> 'object' then
      raise exception using errcode = '22023', message = 'Application metadata must be an object';
    end if;
    insert into platform.platform_apps (slug, name, category, metadata)
    values (p_payload->>'slug', btrim(p_payload->>'name'), btrim(p_payload->>'category'), coalesce(p_payload->'metadata', '{}'::jsonb))
    returning * into app_row;
    target_id := app_row.id;
    target_type := 'platform_app';
    status_code := 201;
    result := jsonb_build_object('id', app_row.id, 'slug', app_row.slug, 'name', app_row.name, 'category', app_row.category,
      'status', app_row.status, 'originCount', 0, 'createdAt', app_row.created_at, 'updatedAt', app_row.updated_at);
    after_summary := jsonb_build_object('id', app_row.id, 'slug', app_row.slug, 'name', app_row.name, 'category', app_row.category);
  elsif p_action = 'update_application' then
    if p_resource_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('name', 'category', 'metadata'))
       or p_expected_updated_at is null then
      raise exception using errcode = '22023', message = 'The application draft fields are invalid';
    end if;
    select app.* into app_row from platform.platform_apps as app where app.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The application was not found'; end if;
    if app_row.updated_at is distinct from p_expected_updated_at then
      raise exception using errcode = '40001', message = 'The application changed before this draft update';
    end if;
    before_summary := jsonb_build_object('id', app_row.id, 'name', app_row.name, 'category', app_row.category);
    update platform.platform_apps
       set name = case when p_payload ? 'name' then btrim(p_payload->>'name') else name end,
           category = case when p_payload ? 'category' then btrim(p_payload->>'category') else category end,
           metadata = case when p_payload ? 'metadata' then p_payload->'metadata' else metadata end
     where id = app_row.id;
    select app.* into app_row from platform.platform_apps as app where app.id = p_resource_id;
    if btrim(app_row.name) = '' or btrim(app_row.category) = '' or jsonb_typeof(app_row.metadata) <> 'object' then
      raise exception using errcode = '22023', message = 'The application draft fields are invalid';
    end if;
    target_id := app_row.id;
    target_type := 'platform_app';
    result := jsonb_build_object('id', app_row.id, 'slug', app_row.slug, 'name', app_row.name, 'category', app_row.category,
      'status', app_row.status, 'originCount', (select count(*)::integer from platform.app_origins where app_id = app_row.id and is_active),
      'createdAt', app_row.created_at, 'updatedAt', app_row.updated_at);
    after_summary := jsonb_build_object('id', app_row.id, 'name', app_row.name, 'category', app_row.category);
  elsif p_action = 'create_origin' then
    if p_resource_id is not null or p_parent_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('environment', 'origin')) then
      raise exception using errcode = '22023', message = 'The Origin draft fields are invalid';
    end if;
    if not exists (select 1 from platform.platform_apps where id = p_parent_id) then
      raise exception using errcode = 'P0002', message = 'The application was not found';
    end if;
    if p_payload->>'environment' not in ('development', 'staging')
       or p_payload->>'origin' !~ '^https?://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?$' then
      raise exception using errcode = '22023', message = 'The Origin draft fields are invalid';
    end if;
    insert into platform.app_origins (app_id, environment, origin)
    values (p_parent_id, p_payload->>'environment', lower(p_payload->>'origin'))
    returning * into origin_row;
    target_id := origin_row.id;
    target_type := 'app_origin';
    status_code := 201;
    result := jsonb_build_object('id', origin_row.id, 'appId', origin_row.app_id,
      'appSlug', (select slug from platform.platform_apps where id = origin_row.app_id), 'environment', origin_row.environment,
      'origin', origin_row.origin, 'isActive', origin_row.is_active, 'createdAt', origin_row.created_at, 'updatedAt', origin_row.updated_at);
    after_summary := jsonb_build_object('id', origin_row.id, 'appId', origin_row.app_id, 'environment', origin_row.environment, 'origin', origin_row.origin);
  elsif p_action = 'update_origin' then
    if p_resource_id is null or p_expected_updated_at is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('isActive'))
       or not (p_payload ? 'isActive') or jsonb_typeof(p_payload->'isActive') <> 'boolean' then
      raise exception using errcode = '22023', message = 'The Origin draft fields are invalid';
    end if;
    select origin.* into origin_row from platform.app_origins as origin where origin.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Origin was not found'; end if;
    if origin_row.updated_at is distinct from p_expected_updated_at then
      raise exception using errcode = '40001', message = 'The Origin changed before this draft update';
    end if;
    before_summary := jsonb_build_object('id', origin_row.id, 'isActive', origin_row.is_active);
    update platform.app_origins set is_active = (p_payload->>'isActive')::boolean where id = origin_row.id;
    select origin.* into origin_row from platform.app_origins as origin where origin.id = p_resource_id;
    target_id := origin_row.id;
    target_type := 'app_origin';
    result := jsonb_build_object('id', origin_row.id, 'appId', origin_row.app_id,
      'appSlug', (select slug from platform.platform_apps where id = origin_row.app_id), 'environment', origin_row.environment,
      'origin', origin_row.origin, 'isActive', origin_row.is_active, 'createdAt', origin_row.created_at, 'updatedAt', origin_row.updated_at);
    after_summary := jsonb_build_object('id', origin_row.id, 'isActive', origin_row.is_active);
  elsif p_action = 'create_feature' then
    if p_resource_id is not null or p_parent_id is not null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('appId', 'code', 'name', 'valueType', 'mergeStrategy')) then
      raise exception using errcode = '22023', message = 'The Feature draft fields are invalid';
    end if;
    if p_payload->>'code' is null or p_payload->>'code' !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
       or btrim(coalesce(p_payload->>'name', '')) = ''
       or p_payload->>'valueType' not in ('boolean', 'integer', 'string', 'json')
       or p_payload->>'mergeStrategy' not in ('any_true', 'sum', 'max', 'min', 'latest') then
      raise exception using errcode = '22023', message = 'The Feature draft fields are invalid';
    end if;
    insert into platform.features (app_id, code, name, value_type, merge_strategy)
    values (case when p_payload ? 'appId' then (p_payload->>'appId')::uuid else null end,
      p_payload->>'code', btrim(p_payload->>'name'), p_payload->>'valueType', p_payload->>'mergeStrategy')
    returning * into feature_row;
    target_id := feature_row.id;
    target_type := 'feature';
    status_code := 201;
    result := jsonb_build_object('id', feature_row.id, 'appSlug', (select slug from platform.platform_apps where id = feature_row.app_id),
      'code', feature_row.code, 'name', feature_row.name, 'valueType', feature_row.value_type, 'status', feature_row.status,
      'mergeStrategy', feature_row.merge_strategy, 'createdAt', feature_row.created_at);
    after_summary := jsonb_build_object('id', feature_row.id, 'code', feature_row.code, 'name', feature_row.name);
  elsif p_action = 'update_feature' then
    if p_resource_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('name', 'mergeStrategy')) then
      raise exception using errcode = '22023', message = 'The Feature draft fields are invalid';
    end if;
    select feature.* into feature_row from platform.features as feature where feature.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Feature was not found'; end if;
    before_summary := jsonb_build_object('id', feature_row.id, 'name', feature_row.name, 'mergeStrategy', feature_row.merge_strategy);
    update platform.features
       set name = case when p_payload ? 'name' then btrim(p_payload->>'name') else name end,
           merge_strategy = case when p_payload ? 'mergeStrategy' then p_payload->>'mergeStrategy' else merge_strategy end
     where id = feature_row.id;
    select feature.* into feature_row from platform.features as feature where feature.id = p_resource_id;
    if btrim(feature_row.name) = '' then raise exception using errcode = '22023', message = 'The Feature draft fields are invalid'; end if;
    target_id := feature_row.id;
    target_type := 'feature';
    result := jsonb_build_object('id', feature_row.id, 'appSlug', (select slug from platform.platform_apps where id = feature_row.app_id),
      'code', feature_row.code, 'name', feature_row.name, 'valueType', feature_row.value_type, 'status', feature_row.status,
      'mergeStrategy', feature_row.merge_strategy, 'createdAt', feature_row.created_at);
    after_summary := jsonb_build_object('id', feature_row.id, 'name', feature_row.name, 'mergeStrategy', feature_row.merge_strategy);
  elsif p_action = 'create_product' then
    if p_resource_id is not null or p_parent_id is not null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('sku', 'name', 'billingType', 'entitlementPolicy')) then
      raise exception using errcode = '22023', message = 'The Product draft fields are invalid';
    end if;
    if p_payload->>'sku' is null or p_payload->>'sku' !~ '^[A-Z0-9][A-Z0-9_-]*$'
       or btrim(coalesce(p_payload->>'name', '')) = ''
       or p_payload->>'billingType' not in ('one_time', 'subscription', 'credits')
       or coalesce(p_payload->>'entitlementPolicy', 'snapshot') not in ('snapshot', 'all_apps_access') then
      raise exception using errcode = '22023', message = 'The Product draft fields are invalid';
    end if;
    insert into platform.products (sku, name, billing_type, entitlement_policy)
    values (p_payload->>'sku', btrim(p_payload->>'name'), p_payload->>'billingType', coalesce(p_payload->>'entitlementPolicy', 'snapshot'))
    returning * into product_row;
    target_id := product_row.id;
    target_type := 'product';
    status_code := 201;
    result := jsonb_build_object('id', product_row.id, 'sku', product_row.sku, 'name', product_row.name, 'billingType', product_row.billing_type,
      'status', product_row.status, 'currentVersion', null);
    after_summary := jsonb_build_object('id', product_row.id, 'sku', product_row.sku, 'name', product_row.name);
  elsif p_action = 'update_product' then
    if p_resource_id is null or p_expected_updated_at is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('name', 'billingType', 'entitlementPolicy')) then
      raise exception using errcode = '22023', message = 'The Product draft fields are invalid';
    end if;
    select product.* into product_row from platform.products as product where product.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Product was not found'; end if;
    if product_row.updated_at is distinct from p_expected_updated_at then
      raise exception using errcode = '40001', message = 'The Product changed before this draft update';
    end if;
    if product_row.status <> 'draft' then raise exception using errcode = '23514', message = 'Only draft products can be edited'; end if;
    before_summary := jsonb_build_object('id', product_row.id, 'name', product_row.name, 'billingType', product_row.billing_type, 'entitlementPolicy', product_row.entitlement_policy);
    update platform.products
       set name = case when p_payload ? 'name' then btrim(p_payload->>'name') else name end,
           billing_type = case when p_payload ? 'billingType' then p_payload->>'billingType' else billing_type end,
           entitlement_policy = case when p_payload ? 'entitlementPolicy' then p_payload->>'entitlementPolicy' else entitlement_policy end
     where id = product_row.id;
    select product.* into product_row from platform.products as product where product.id = p_resource_id;
    if btrim(product_row.name) = '' then raise exception using errcode = '22023', message = 'The Product draft fields are invalid'; end if;
    target_id := product_row.id;
    target_type := 'product';
    result := jsonb_build_object('id', product_row.id, 'sku', product_row.sku, 'name', product_row.name, 'billingType', product_row.billing_type,
      'status', product_row.status, 'currentVersion', null);
    after_summary := jsonb_build_object('id', product_row.id, 'name', product_row.name, 'billingType', product_row.billing_type, 'entitlementPolicy', product_row.entitlement_policy);
  elsif p_action = 'create_product_version' then
    if p_resource_id is not null or p_parent_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('version', 'accessDurationDays', 'salesTerms')) then
      raise exception using errcode = '22023', message = 'The Product Version draft fields are invalid';
    end if;
    if not exists (select 1 from platform.products where id = p_parent_id) or p_payload->>'version' is null then
      raise exception using errcode = '22023', message = 'The Product Version draft fields are invalid';
    end if;
    if p_payload ? 'salesTerms' and jsonb_typeof(p_payload->'salesTerms') <> 'object' then
      raise exception using errcode = '22023', message = 'Sales terms must be an object';
    end if;
    insert into platform.product_versions (product_id, version, access_duration_days, sales_terms)
    values (p_parent_id, (p_payload->>'version')::integer,
      case when p_payload ? 'accessDurationDays' then (p_payload->>'accessDurationDays')::integer else null end,
      coalesce(p_payload->'salesTerms', '{}'::jsonb))
    returning * into version_row;
    target_id := version_row.id;
    target_type := 'product_version';
    status_code := 201;
    result := jsonb_build_object('id', version_row.id, 'productId', version_row.product_id,
      'productSku', (select sku from platform.products where id = version_row.product_id), 'version', version_row.version,
      'status', version_row.status, 'publishedAt', version_row.published_at);
    after_summary := jsonb_build_object('id', version_row.id, 'productId', version_row.product_id, 'version', version_row.version);
  elsif p_action = 'update_product_version' then
    if p_resource_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('accessDurationDays', 'salesTerms')) then
      raise exception using errcode = '22023', message = 'The Product Version draft fields are invalid';
    end if;
    select version.* into version_row from platform.product_versions as version where version.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Product Version was not found'; end if;
    if version_row.status <> 'draft' then raise exception using errcode = '23514', message = 'Only draft product versions can be edited'; end if;
    if p_payload ? 'salesTerms' and jsonb_typeof(p_payload->'salesTerms') <> 'object' then
      raise exception using errcode = '22023', message = 'Sales terms must be an object';
    end if;
    update platform.product_versions
       set access_duration_days = case when p_payload ? 'accessDurationDays' then (p_payload->>'accessDurationDays')::integer else access_duration_days end,
           sales_terms = case when p_payload ? 'salesTerms' then p_payload->'salesTerms' else sales_terms end
     where id = version_row.id;
    select version.* into version_row from platform.product_versions as version where version.id = p_resource_id;
    target_id := version_row.id;
    target_type := 'product_version';
    result := jsonb_build_object('id', version_row.id, 'productId', version_row.product_id,
      'productSku', (select sku from platform.products where id = version_row.product_id), 'version', version_row.version,
      'status', version_row.status, 'publishedAt', version_row.published_at);
    after_summary := jsonb_build_object('id', version_row.id, 'accessDurationDays', version_row.access_duration_days);
  elsif p_action = 'create_price' then
    if p_resource_id is not null or p_parent_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('currency', 'amountMinor', 'channel', 'externalPriceId', 'validFrom', 'validUntil')) then
      raise exception using errcode = '22023', message = 'The Price draft fields are invalid';
    end if;
    if not exists (select 1 from platform.product_versions where id = p_parent_id)
       or p_payload->>'currency' !~ '^[A-Z]{3}$' or p_payload->>'amountMinor' is null
       or p_payload->>'channel' is null then
      raise exception using errcode = '22023', message = 'The Price draft fields are invalid';
    end if;
    insert into platform.product_prices (product_version_id, currency, amount_minor, channel, external_price_id, valid_from, valid_until)
    values (p_parent_id, p_payload->>'currency', (p_payload->>'amountMinor')::bigint, p_payload->>'channel',
      nullif(p_payload->>'externalPriceId', ''),
      coalesce(case when p_payload ? 'validFrom' then (p_payload->>'validFrom')::timestamptz else null end, timezone('utc', now())),
      case when p_payload ? 'validUntil' then (p_payload->>'validUntil')::timestamptz else null end)
    returning * into price_row;
    target_id := price_row.id;
    target_type := 'product_price';
    status_code := 201;
    result := jsonb_build_object('id', price_row.id, 'productId', (select product_id from platform.product_versions where id = price_row.product_version_id),
      'productSku', (select product.sku from platform.products as product join platform.product_versions as version on version.product_id = product.id where version.id = price_row.product_version_id),
      'productVersion', (select version from platform.product_versions where id = price_row.product_version_id), 'currency', price_row.currency,
      'amountMinor', price_row.amount_minor, 'channel', price_row.channel, 'externalPriceId', price_row.external_price_id,
      'status', price_row.status, 'validFrom', price_row.valid_from, 'validUntil', price_row.valid_until, 'createdAt', price_row.created_at, 'updatedAt', price_row.updated_at);
    after_summary := jsonb_build_object('id', price_row.id, 'productVersionId', price_row.product_version_id, 'currency', price_row.currency, 'amountMinor', price_row.amount_minor, 'channel', price_row.channel);
  elsif p_action = 'update_price' then
    if p_resource_id is null or p_expected_updated_at is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('currency', 'amountMinor', 'channel', 'externalPriceId', 'validFrom', 'validUntil')) then
      raise exception using errcode = '22023', message = 'The Price draft fields are invalid';
    end if;
    select price.* into price_row from platform.product_prices as price where price.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Price was not found'; end if;
    if price_row.updated_at is distinct from p_expected_updated_at then
      raise exception using errcode = '40001', message = 'The Price changed before this draft update';
    end if;
    if price_row.status <> 'draft' then raise exception using errcode = '23514', message = 'Only draft prices can be edited'; end if;
    before_summary := jsonb_build_object('id', price_row.id, 'currency', price_row.currency, 'amountMinor', price_row.amount_minor, 'channel', price_row.channel);
    update platform.product_prices
       set currency = case when p_payload ? 'currency' then p_payload->>'currency' else currency end,
           amount_minor = case when p_payload ? 'amountMinor' then (p_payload->>'amountMinor')::bigint else amount_minor end,
           channel = case when p_payload ? 'channel' then p_payload->>'channel' else channel end,
           external_price_id = case when p_payload ? 'externalPriceId' then nullif(p_payload->>'externalPriceId', '') else external_price_id end,
           valid_from = case when p_payload ? 'validFrom' then (p_payload->>'validFrom')::timestamptz else valid_from end,
           valid_until = case when p_payload ? 'validUntil' then (p_payload->>'validUntil')::timestamptz else valid_until end
     where id = price_row.id;
    select price.* into price_row from platform.product_prices as price where price.id = p_resource_id;
    target_id := price_row.id;
    target_type := 'product_price';
    result := jsonb_build_object('id', price_row.id, 'productId', (select product_id from platform.product_versions where id = price_row.product_version_id),
      'productSku', (select product.sku from platform.products as product join platform.product_versions as version on version.product_id = product.id where version.id = price_row.product_version_id),
      'productVersion', (select version from platform.product_versions where id = price_row.product_version_id), 'currency', price_row.currency,
      'amountMinor', price_row.amount_minor, 'channel', price_row.channel, 'externalPriceId', price_row.external_price_id,
      'status', price_row.status, 'validFrom', price_row.valid_from, 'validUntil', price_row.valid_until, 'createdAt', price_row.created_at, 'updatedAt', price_row.updated_at);
    after_summary := jsonb_build_object('id', price_row.id, 'currency', price_row.currency, 'amountMinor', price_row.amount_minor, 'channel', price_row.channel);
  else
    raise exception using errcode = '22023', message = 'The draft command is not supported';
  end if;

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('admin', p_actor_id, p_action, target_type, target_id, p_request_id, p_reason, before_summary, coalesce(after_summary, result));

  update platform.idempotency_records
     set status = 'completed', resource_type = target_type, resource_id = target_id,
         response_status = status_code, response_body = result
   where id = idempotency_row.id;
  return result;
end;
$_$;


ALTER FUNCTION "public"."admin_catalog_draft_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_parent_id" "uuid", "p_payload" "jsonb", "p_expected_updated_at" timestamp with time zone, "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_catalog_draft_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_parent_id" "uuid", "p_payload" "jsonb", "p_expected_updated_at" timestamp with time zone, "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") IS 'Executes explicit, audited Catalog draft create/edit actions with allowlisted fields and idempotent retries.';



CREATE OR REPLACE FUNCTION "public"."admin_catalog_resource_detail"("p_actor_id" "uuid", "p_resource" "text", "p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  actor_role text;
  result jsonb;
begin
  select member.role into actor_role from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if actor_role is null then
    raise exception using errcode = '42501', message = 'Active Admin membership is required';
  end if;
  if p_resource not in ('applications', 'origins', 'features', 'products', 'product-versions', 'prices', 'redemption-batches', 'redemption-codes', 'redemptions', 'entitlements') then
    raise exception using errcode = '22023', message = 'The Catalog detail resource is not supported';
  end if;
  if p_resource in ('applications', 'origins') and actor_role = 'finance' then
    raise exception using errcode = '42501', message = 'The Admin role cannot read this resource';
  end if;

  if p_resource = 'applications' then
    select jsonb_build_object('id', app.id, 'slug', app.slug, 'name', app.name, 'category', app.category, 'status', app.status,
      'originCount', (select count(*)::integer from platform.app_origins as origin where origin.app_id = app.id and origin.is_active), 'createdAt', app.created_at, 'updatedAt', app.updated_at)
      into result from platform.platform_apps as app where app.id = p_id;
  elsif p_resource = 'origins' then
    select jsonb_build_object('id', origin.id, 'appId', origin.app_id, 'appSlug', app.slug, 'environment', origin.environment, 'origin', origin.origin, 'isActive', origin.is_active, 'createdAt', origin.created_at, 'updatedAt', origin.updated_at)
      into result from platform.app_origins as origin join platform.platform_apps as app on app.id = origin.app_id where origin.id = p_id;
  elsif p_resource = 'features' then
    select jsonb_build_object('id', feature.id, 'appSlug', app.slug, 'code', feature.code, 'name', feature.name, 'valueType', feature.value_type, 'status', feature.status, 'mergeStrategy', feature.merge_strategy, 'createdAt', feature.created_at)
      into result from platform.features as feature left join platform.platform_apps as app on app.id = feature.app_id where feature.id = p_id;
  elsif p_resource = 'products' then
    select jsonb_build_object('id', product.id, 'sku', product.sku, 'name', product.name, 'billingType', product.billing_type, 'status', product.status,
      'currentVersion', case when version.id is null then null else jsonb_build_object('id', version.id, 'version', version.version, 'status', version.status) end)
      into result from platform.products as product left join platform.product_versions as version on version.id = product.current_version_id where product.id = p_id;
  elsif p_resource = 'product-versions' then
    select jsonb_build_object('id', version.id, 'productId', version.product_id, 'productSku', product.sku, 'version', version.version, 'status', version.status, 'publishedAt', version.published_at)
      into result from platform.product_versions as version join platform.products as product on product.id = version.product_id where version.id = p_id;
  elsif p_resource = 'prices' then
    select jsonb_build_object('id', price.id, 'productId', product.id, 'productSku', product.sku, 'productVersion', version.version, 'currency', price.currency, 'amountMinor', price.amount_minor, 'channel', price.channel, 'externalPriceId', price.external_price_id, 'status', price.status, 'validFrom', price.valid_from, 'validUntil', price.valid_until, 'createdAt', price.created_at, 'updatedAt', price.updated_at)
      into result from platform.product_prices as price join platform.product_versions as version on version.id = price.product_version_id join platform.products as product on product.id = version.product_id where price.id = p_id;
  elsif p_resource = 'redemption-batches' then
    select jsonb_build_object('id', batch.id, 'name', batch.name, 'productSku', product.sku, 'productVersion', version.version, 'status', batch.status, 'codePrefix', batch.code_prefix, 'quantity', batch.quantity,
      'issuedCount', (select count(*)::integer from platform.redemption_codes as code where code.batch_id = batch.id), 'redeemedCount', (select count(*)::integer from platform.redemptions as redemption where redemption.batch_id = batch.id), 'startsAt', batch.starts_at, 'expiresAt', batch.expires_at, 'createdAt', batch.created_at)
      into result from platform.redemption_batches as batch join platform.products as product on product.id = batch.product_id join platform.product_versions as version on version.id = batch.product_version_id where batch.id = p_id;
  elsif p_resource = 'redemption-codes' then
    select jsonb_build_object('id', code.id, 'batchId', code.batch_id, 'codeHint', code.code_hint, 'status', code.status, 'redeemedAt', code.redeemed_at)
      into result from platform.redemption_codes as code where code.id = p_id;
  elsif p_resource = 'redemptions' then
    select jsonb_build_object('id', redemption.id, 'batchId', redemption.batch_id, 'userId', redemption.user_id, 'productSku', product.sku, 'status', 'redeemed', 'redeemedAt', redemption.redeemed_at)
      into result from platform.redemptions as redemption join platform.redemption_batches as batch on batch.id = redemption.batch_id join platform.products as product on product.id = batch.product_id where redemption.id = p_id;
  elsif p_resource = 'entitlements' then
    select jsonb_build_object('id', grant_item.id, 'userId', grant_item.user_id, 'displayName', case when actor_role = 'finance' then null else profile.display_name end, 'productSku', product.sku, 'productVersion', version.version, 'sourceType', grant_item.source_type, 'status', grant_item.status, 'startsAt', grant_item.starts_at, 'expiresAt', grant_item.expires_at, 'createdAt', grant_item.created_at)
      into result from platform.entitlement_grants as grant_item join platform.products as product on product.id = grant_item.product_id join platform.product_versions as version on version.id = grant_item.product_version_id join platform.profiles as profile on profile.id = grant_item.user_id where grant_item.id = p_id;
  end if;

  if result is null then
    raise exception using errcode = 'P0002', message = 'The Catalog resource was not found';
  end if;
  return result;
end;
$$;


ALTER FUNCTION "public"."admin_catalog_resource_detail"("p_actor_id" "uuid", "p_resource" "text", "p_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_catalog_resource_detail"("p_actor_id" "uuid", "p_resource" "text", "p_id" "uuid") IS 'Returns one explicit Catalog or Redemption projection without sensitive code material.';



CREATE OR REPLACE FUNCTION "public"."admin_customer_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb" DEFAULT '{}'::"jsonb", "p_reason" "text" DEFAULT NULL::"text", "p_idempotency_key" "text" DEFAULT NULL::"text", "p_request_hash" "text" DEFAULT NULL::"text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'auth', 'platform'
    AS $$
declare
  actor_role text;
  idempotency_row platform.idempotency_records%rowtype;
  profile_row platform.profiles%rowtype;
  grant_row platform.entitlement_grants%rowtype;
  deletion_row platform.account_deletion_requests%rowtype;
  grant_result record;
  audit_id_value uuid;
  now_value timestamptz := timezone('utc', now());
  previous_deletion_status text;
  result jsonb;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';

  if actor_role is null then
    raise exception using errcode = '42501', message = 'Customer commands require an active administrator';
  end if;
  if p_action not in ('grant_entitlement', 'revoke_entitlement', 'restore_entitlement',
                      'disable_user', 'process_account_deletion') then
    raise exception using errcode = '22023', message = 'The Customer command is not supported';
  end if;
  if p_resource_id is null or p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'The Customer command target or payload is invalid';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A Customer command reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  if p_action in ('restore_entitlement', 'disable_user', 'process_account_deletion')
     and actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'This Customer command requires an owner or administrator';
  end if;
  if p_action in ('grant_entitlement', 'revoke_entitlement')
     and actor_role not in ('owner', 'admin', 'support') then
    raise exception using errcode = '42501', message = 'This Entitlement command is not allowed for the administrator';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.customer.command', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     now_value + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.customer.command'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body;
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The Customer command is already in progress';
    end if;
  end if;

  if p_action = 'grant_entitlement' then
    if actor_role not in ('owner', 'admin', 'support')
       or exists (select 1 from jsonb_object_keys(p_payload) as key
                  where key not in ('productVersionId', 'startsAt', 'expiresAt'))
       or p_payload->>'productVersionId' is null then
      raise exception using errcode = '22023', message = 'The Entitlement grant fields are invalid';
    end if;
    select profile.* into profile_row
      from platform.profiles as profile
     where profile.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The User was not found';
    end if;
    if profile_row.status <> 'active' then
      raise exception using errcode = '23514', message = 'Only active users can receive an entitlement grant';
    end if;
    select granted.* into grant_result
      from public.grant_entitlement(
        p_resource_id,
        (p_payload->>'productVersionId')::uuid,
        'admin',
        null,
        coalesce((p_payload->>'startsAt')::timestamptz, now_value),
        (p_payload->>'expiresAt')::timestamptz,
        'admin',
        p_actor_id,
        p_reason,
        null,
        p_request_id
      ) as granted;
    result := jsonb_build_object(
      'grantId', grant_result.grant_id,
      'sourceId', grant_result.source_id,
      'status', grant_result.status,
      'startsAt', grant_result.starts_at,
      'expiresAt', grant_result.expires_at,
      'auditLogId', grant_result.audit_log_id
    );
  elsif p_action = 'revoke_entitlement' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key) then
      raise exception using errcode = '22023', message = 'Entitlement revoke does not accept additional fields';
    end if;
    select grant_item.* into grant_row
      from platform.entitlement_grants as grant_item
     where grant_item.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Entitlement grant was not found';
    end if;
    select revoked.* into grant_result
      from public.revoke_entitlement(p_resource_id, 'admin', p_actor_id, p_reason, p_request_id) as revoked;
    result := jsonb_build_object(
      'grantId', grant_result.grant_id,
      'status', grant_result.status,
      'revokedAt', grant_result.revoked_at,
      'auditLogId', grant_result.audit_log_id
    );
  elsif p_action = 'restore_entitlement' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key) then
      raise exception using errcode = '22023', message = 'Entitlement restore does not accept additional fields';
    end if;
    select grant_item.* into grant_row
      from platform.entitlement_grants as grant_item
     where grant_item.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Entitlement grant was not found';
    end if;
    select restored.* into grant_result
      from public.restore_entitlement(p_resource_id, p_actor_id, p_reason, p_request_id) as restored;
    result := jsonb_build_object(
      'grantId', grant_result.grant_id,
      'sourceId', grant_result.source_id,
      'status', grant_result.status,
      'startsAt', grant_result.starts_at,
      'expiresAt', grant_result.expires_at,
      'restoredGrantId', grant_result.grant_id,
      'restoresGrantId', p_resource_id,
      'auditLogId', grant_result.audit_log_id
    );
  elsif p_action = 'disable_user' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key) then
      raise exception using errcode = '22023', message = 'User disable does not accept additional fields';
    end if;
    select profile.* into profile_row
      from platform.profiles as profile
     where profile.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The User was not found';
    end if;
    if profile_row.status <> 'active' then
      raise exception using errcode = '23514', message = 'Only active users can be disabled';
    end if;
    update platform.profiles
       set status = 'disabled'
     where id = p_resource_id;
    result := jsonb_build_object(
      'userId', p_resource_id,
      'status', 'disabled'
    );
    insert into platform.audit_logs
      (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
    values
      ('admin', p_actor_id, 'users.disable', 'user', p_resource_id, p_request_id, p_reason,
       jsonb_build_object('status', profile_row.status), result)
    returning id into audit_id_value;
    result := result || jsonb_build_object('auditLogId', audit_id_value);
  elsif p_action = 'process_account_deletion' then
    if exists (select 1 from jsonb_object_keys(p_payload) as key) then
      raise exception using errcode = '22023', message = 'Deletion processing does not accept additional fields';
    end if;
    select request_item.* into deletion_row
      from platform.account_deletion_requests as request_item
     where request_item.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The account deletion request was not found';
    end if;
    if deletion_row.status not in ('pending', 'failed')
       or deletion_row.execute_after > now_value
       or (deletion_row.next_attempt_at is not null and deletion_row.next_attempt_at > now_value) then
      raise exception using errcode = '23514', message = 'The account deletion request is not ready to process';
    end if;
    previous_deletion_status := deletion_row.status;
    update platform.account_deletion_requests
       set status = 'processing',
           attempt_count = deletion_row.attempt_count + 1,
           last_error_code = null,
           next_attempt_at = null,
           worker_id = p_actor_id,
           processing_started_at = now_value
     where id = p_resource_id
     returning * into deletion_row;
    result := jsonb_build_object(
      'deletionRequestId', deletion_row.id,
      'userId', deletion_row.user_id,
      'status', deletion_row.status,
      'attemptCount', deletion_row.attempt_count,
      'processingStartedAt', deletion_row.processing_started_at
    );
    insert into platform.audit_logs
      (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
    values
      ('admin', p_actor_id, 'account.deletion.process', 'account_deletion_request', deletion_row.id,
       p_request_id, p_reason,
       jsonb_build_object('status', previous_deletion_status, 'attemptCount', deletion_row.attempt_count - 1), result)
    returning id into audit_id_value;
    result := result || jsonb_build_object('auditLogId', audit_id_value);
  end if;

  update platform.idempotency_records
     set status = 'completed',
         resource_type = case
           when p_action in ('grant_entitlement', 'revoke_entitlement', 'restore_entitlement')
             then 'entitlement_grant'
           when p_action = 'process_account_deletion'
             then 'account_deletion_request'
           else 'user'
         end,
         resource_id = case when p_action = 'grant_entitlement' then (result->>'grantId')::uuid
                            when p_action = 'restore_entitlement' then (result->>'restoredGrantId')::uuid
                            else p_resource_id end,
         response_status = 200,
         response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;


ALTER FUNCTION "public"."admin_customer_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_customer_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") IS 'Executes named Customer commands with role checks, domain transactions, append-only audit, and idempotent retries.';



CREATE OR REPLACE FUNCTION "public"."admin_list_application_memberships"("p_actor_id" "uuid", "p_application_id" "uuid") RETURNS TABLE("id" "uuid", "application_id" "uuid", "application_slug" "text", "application_name" "text", "user_id" "uuid", "membership_status" "text", "created_source" "text", "joined_at" timestamp with time zone, "activated_at" timestamp with time zone, "suspended_at" timestamp with time zone, "suspended_reason" "text", "left_at" timestamp with time zone, "deleted_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  actor_role text;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if coalesce(actor_role in ('owner', 'admin', 'support'), false) = false then
    raise exception using errcode = '42501', message = 'Application membership access requires an Admin member';
  end if;
  if p_application_id is null then
    raise exception using errcode = '22023', message = 'Application id is required';
  end if;
  return query
  select membership.id,
         app.id,
         app.slug,
         app.name,
         membership.user_id,
         membership.status,
         membership.created_source,
         membership.joined_at,
         membership.activated_at,
         membership.suspended_at,
         membership.suspended_reason,
         membership.left_at,
         membership.deleted_at
    from platform.application_memberships as membership
    join platform.platform_apps as app on app.id = membership.application_id
   where membership.application_id = p_application_id
   order by membership.joined_at desc, membership.id desc;
end;
$$;


ALTER FUNCTION "public"."admin_list_application_memberships"("p_actor_id" "uuid", "p_application_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_list_application_memberships"("p_actor_id" "uuid", "p_application_id" "uuid") IS 'Returns safe member summaries for an authorized Admin and one Application.';



CREATE OR REPLACE FUNCTION "public"."admin_list_application_oauth_clients"("p_actor_id" "uuid", "p_application_id" "uuid") RETURNS TABLE("id" "uuid", "application_id" "uuid", "provider" "text", "external_client_id" "text", "client_type" "text", "environment" "text", "name" "text", "status" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  actor_role text;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if coalesce(actor_role in ('owner', 'admin', 'support'), false) = false then
    raise exception using errcode = '42501', message = 'OAuth client access requires an Admin member';
  end if;
  if p_application_id is null then
    raise exception using errcode = '22023', message = 'Application id is required';
  end if;
  return query
  select client.id,
         client.application_id,
         client.provider,
         client.external_client_id,
         client.client_type,
         client.environment,
         client.name,
         client.status,
         client.created_at,
         client.updated_at
    from platform.application_oauth_clients as client
   where client.application_id = p_application_id
   order by client.environment, client.name, client.id;
end;
$$;


ALTER FUNCTION "public"."admin_list_application_oauth_clients"("p_actor_id" "uuid", "p_application_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_list_application_oauth_clients"("p_actor_id" "uuid", "p_application_id" "uuid") IS 'Returns OAuth client binding metadata without provider secrets or redirect configuration.';



CREATE OR REPLACE FUNCTION "public"."admin_oauth_client_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_client_id" "uuid" DEFAULT NULL::"uuid", "p_provider" "text" DEFAULT NULL::"text", "p_external_client_id" "text" DEFAULT NULL::"text", "p_client_type" "text" DEFAULT NULL::"text", "p_environment" "text" DEFAULT NULL::"text", "p_name" "text" DEFAULT NULL::"text", "p_reason" "text" DEFAULT NULL::"text", "p_idempotency_key" "text" DEFAULT NULL::"text", "p_request_hash" "text" DEFAULT NULL::"text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  actor_role text;
  app_row platform.platform_apps%rowtype;
  client_row platform.application_oauth_clients%rowtype;
  idempotency_row platform.idempotency_records%rowtype;
  audit_id uuid := gen_random_uuid();
  before_summary jsonb := '{}'::jsonb;
  after_summary jsonb;
  result jsonb;
begin
  select member.role into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'OAuth client commands require an owner or administrator';
  end if;
  if p_action not in ('create', 'disable', 'restore') or p_application_id is null then
    raise exception using errcode = '22023', message = 'The OAuth client command fields are invalid';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'An OAuth client command reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.oauth_client.command', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.* into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.oauth_client.command'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body;
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The OAuth client command is already in progress';
    end if;
  end if;

  select app.* into app_row
    from platform.platform_apps as app
   where app.id = p_application_id
     and app.status = 'active'
   for share;
  if not found then
    raise exception using errcode = 'P0002', message = 'The active Application was not found';
  end if;

  if p_action = 'create' then
    if p_client_id is not null or p_provider is null or btrim(p_provider) = ''
       or p_external_client_id is null or btrim(p_external_client_id) = ''
       or p_client_type is null or p_environment is null or p_name is null or btrim(p_name) = '' then
      raise exception using errcode = '22023', message = 'OAuth client creation fields are invalid';
    end if;
    insert into platform.application_oauth_clients
      (application_id, provider, external_client_id, client_type, environment, name)
    values
      (p_application_id, btrim(p_provider), btrim(p_external_client_id), p_client_type,
       p_environment, btrim(p_name))
    returning * into client_row;
  else
    if p_client_id is null then
      raise exception using errcode = '22023', message = 'OAuth client id is required';
    end if;
    select client.* into client_row
      from platform.application_oauth_clients as client
     where client.id = p_client_id
       and client.application_id = p_application_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The OAuth client binding was not found';
    end if;
    before_summary := jsonb_build_object('id', client_row.id, 'status', client_row.status);
    if p_action = 'disable' then
      if client_row.status <> 'active' then
        raise exception using errcode = '23514', message = 'Only an active OAuth client can be disabled';
      end if;
      update platform.application_oauth_clients set status = 'disabled' where id = client_row.id;
    elsif client_row.status <> 'disabled' then
      raise exception using errcode = '23514', message = 'Only a disabled OAuth client can be restored';
    else
      update platform.application_oauth_clients set status = 'active' where id = client_row.id;
    end if;
    select client.* into client_row from platform.application_oauth_clients as client where client.id = p_client_id;
  end if;

  after_summary := jsonb_build_object('id', client_row.id, 'applicationId', client_row.application_id,
    'provider', client_row.provider, 'externalClientId', client_row.external_client_id,
    'clientType', client_row.client_type, 'environment', client_row.environment,
    'name', client_row.name, 'status', client_row.status);
  result := jsonb_build_object(
    'id', client_row.id,
    'applicationId', client_row.application_id,
    'provider', client_row.provider,
    'externalClientId', client_row.external_client_id,
    'clientType', client_row.client_type,
    'environment', client_row.environment,
    'name', client_row.name,
    'status', client_row.status,
    'createdAt', client_row.created_at,
    'updatedAt', client_row.updated_at
  );
  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason,
     before_summary, after_summary)
  values
    (audit_id, 'admin', p_actor_id, 'applications.oauth_client.' || p_action,
     'application_oauth_client', client_row.id, p_request_id, btrim(p_reason),
     before_summary, after_summary);
  result := result || jsonb_build_object('auditLogId', audit_id);
  update platform.idempotency_records
     set status = 'completed', resource_type = 'application_oauth_client', resource_id = client_row.id,
         response_status = 200, response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;


ALTER FUNCTION "public"."admin_oauth_client_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_client_id" "uuid", "p_provider" "text", "p_external_client_id" "text", "p_client_type" "text", "p_environment" "text", "p_name" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_oauth_client_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_client_id" "uuid", "p_provider" "text", "p_external_client_id" "text", "p_client_type" "text", "p_environment" "text", "p_name" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") IS 'Executes owner/admin-only OAuth client binding commands without accepting or storing provider secrets.';



CREATE OR REPLACE FUNCTION "public"."admin_operations_overview"("p_actor_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."admin_operations_overview"("p_actor_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_operations_overview"("p_actor_id" "uuid") IS 'Returns fixed, role-filtered operational counts and fixed Admin drill-down paths without PII or arbitrary query input.';



CREATE OR REPLACE FUNCTION "public"."admin_order_overview"("p_actor_id" "uuid", "p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."admin_order_overview"("p_actor_id" "uuid", "p_order_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_order_overview"("p_actor_id" "uuid", "p_order_id" "uuid") IS 'Returns one role-filtered Order 360 aggregate including item grants, refunds, exceptions, safe payment/event summaries, and audit timeline.';



CREATE OR REPLACE FUNCTION "public"."admin_product_overview"("p_actor_id" "uuid", "p_product_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  actor_role text;
  product_row jsonb;
begin
  select member.role into actor_role from platform.admin_members as member
   where member.user_id = p_actor_id and member.status = 'active';
  if actor_role is null then
    raise exception using errcode = '42501', message = 'Active Admin membership is required';
  end if;
  select jsonb_build_object('id', product.id, 'sku', product.sku, 'name', product.name, 'billingType', product.billing_type, 'status', product.status,
    'currentVersion', case when current_version.id is null then null else jsonb_build_object('id', current_version.id, 'version', current_version.version, 'status', current_version.status) end)
    into product_row
    from platform.products as product left join platform.product_versions as current_version on current_version.id = product.current_version_id
   where product.id = p_product_id;
  if product_row is null then
    raise exception using errcode = 'P0002', message = 'The Product was not found';
  end if;
  return jsonb_build_object(
    'product', product_row,
    'versions', coalesce((select jsonb_agg(jsonb_build_object('id', version.id, 'productId', version.product_id, 'productSku', product.sku, 'version', version.version, 'status', version.status, 'publishedAt', version.published_at) order by version.version desc)
      from platform.product_versions as version join platform.products as product on product.id = version.product_id where version.product_id = p_product_id), '[]'::jsonb),
    'prices', coalesce((select jsonb_agg(jsonb_build_object('id', price.id, 'productId', product.id, 'productSku', product.sku, 'productVersion', version.version, 'currency', price.currency, 'amountMinor', price.amount_minor, 'channel', price.channel, 'externalPriceId', price.external_price_id, 'status', price.status, 'validFrom', price.valid_from, 'validUntil', price.valid_until, 'createdAt', price.created_at, 'updatedAt', price.updated_at) order by price.created_at desc)
      from platform.product_prices as price join platform.product_versions as version on version.id = price.product_version_id join platform.products as product on product.id = version.product_id where product.id = p_product_id), '[]'::jsonb),
    'featureSnapshots', coalesce((select jsonb_agg(jsonb_build_object('featureCode', feature.code, 'value', snapshot.value) order by feature.code)
      from platform.product_version_features as snapshot join platform.features as feature on feature.id = snapshot.feature_id join platform.product_versions as version on version.id = snapshot.product_version_id where version.product_id = p_product_id), '[]'::jsonb),
    'redemptionBatches', coalesce((select jsonb_agg(jsonb_build_object('id', batch.id, 'name', batch.name, 'productSku', product.sku, 'productVersion', version.version, 'status', batch.status, 'codePrefix', batch.code_prefix, 'quantity', batch.quantity,
        'issuedCount', (select count(*)::integer from platform.redemption_codes as code where code.batch_id = batch.id), 'redeemedCount', (select count(*)::integer from platform.redemptions as redemption where redemption.batch_id = batch.id),
        'startsAt', batch.starts_at, 'expiresAt', batch.expires_at, 'createdAt', batch.created_at) order by batch.created_at desc)
      from platform.redemption_batches as batch join platform.products as product on product.id = batch.product_id join platform.product_versions as version on version.id = batch.product_version_id where batch.product_id = p_product_id), '[]'::jsonb),
    'auditLogs', coalesce((select jsonb_agg(jsonb_build_object('id', audit.id, 'actorType', audit.actor_type, 'actorId', audit.actor_id, 'action', audit.action, 'targetType', audit.target_type, 'targetId', audit.target_id, 'requestId', audit.request_id, 'reason', audit.reason, 'beforeSummary', audit.before_summary, 'afterSummary', audit.after_summary, 'createdAt', audit.created_at) order by audit.created_at desc)
      from platform.audit_logs as audit where audit.target_id = p_product_id or audit.target_id in (select version.id from platform.product_versions as version where version.product_id = p_product_id)), '[]'::jsonb)
  );
end;
$$;


ALTER FUNCTION "public"."admin_product_overview"("p_actor_id" "uuid", "p_product_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_product_overview"("p_actor_id" "uuid", "p_product_id" "uuid") IS 'Returns one Product 360 projection composed from existing Catalog, Redemption, and Audit facts.';



CREATE OR REPLACE FUNCTION "public"."admin_query_catalog_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 25, "p_search" "text" DEFAULT NULL::"text", "p_status" "text" DEFAULT NULL::"text", "p_sort" "text" DEFAULT 'createdAt'::"text", "p_direction" "text" DEFAULT 'desc'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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
  if p_resource not in ('origins', 'features', 'product-versions', 'prices', 'redemption-batches', 'redemption-codes') then
    raise exception using errcode = '22023', message = 'The Catalog resource is not supported';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'The Catalog page size is invalid';
  end if;
  if p_direction not in ('asc', 'desc') then
    raise exception using errcode = '22023', message = 'The Catalog sort direction is invalid';
  end if;
  if p_search is not null and (length(p_search) < 1 or length(p_search) > 200) then
    raise exception using errcode = '22023', message = 'The Catalog search value is invalid';
  end if;
  if p_cursor is not null then
    begin
      cursor_json := convert_from(decode(p_cursor, 'base64'), 'utf8')::jsonb;
      cursor_value := cursor_json ->> 'value';
      cursor_id := (cursor_json ->> 'id')::uuid;
    exception when others then
      raise exception using errcode = '22023', message = 'The Catalog cursor is invalid';
    end;
  end if;

  if p_resource = 'origins' then
    if actor_role = 'finance' then
      raise exception using errcode = '42501', message = 'The Admin role cannot read origins';
    end if;
    if p_status is not null or p_sort not in ('createdAt', 'updatedAt', 'origin', 'environment') then
      raise exception using errcode = '22023', message = 'The Origin query is invalid';
    end if;
    return (
      with base as (
        select origin.id, origin.app_id, app.slug as app_slug, origin.environment, origin.origin,
               origin.is_active, origin.created_at, origin.updated_at,
               case p_sort when 'updatedAt' then to_char(origin.updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
                 when 'origin' then origin.origin when 'environment' then origin.environment
                 else to_char(origin.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.app_origins as origin join platform.platform_apps as app on app.id = origin.app_id
         where (p_search is null or app.slug ilike '%' || p_search || '%' or origin.origin ilike '%' || p_search || '%')
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'appId', app_id, 'appSlug', app_slug, 'environment', environment, 'origin', origin, 'isActive', is_active, 'createdAt', created_at, 'updatedAt', updated_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  if p_resource = 'features' then
    if p_sort not in ('createdAt', 'code', 'name', 'status') then
      raise exception using errcode = '22023', message = 'The Feature query is invalid';
    end if;
    return (
      with base as (
        select feature.id, app.slug as app_slug, feature.code, feature.name, feature.value_type, feature.status, feature.merge_strategy, feature.created_at,
               case p_sort when 'code' then feature.code when 'name' then feature.name when 'status' then feature.status
                 else to_char(feature.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.features as feature left join platform.platform_apps as app on app.id = feature.app_id
         where (p_search is null or feature.code ilike '%' || p_search || '%' or feature.name ilike '%' || p_search || '%')
           and (p_status is null or feature.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'appSlug', app_slug, 'code', code, 'name', name, 'valueType', value_type, 'status', status, 'mergeStrategy', merge_strategy, 'createdAt', created_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  if p_resource = 'product-versions' then
    if p_sort not in ('createdAt', 'version', 'status') then
      raise exception using errcode = '22023', message = 'The Product Version query is invalid';
    end if;
    return (
      with base as (
        select version.id, version.product_id, product.sku as product_sku, version.version, version.status, version.published_at, version.created_at,
               case p_sort when 'version' then lpad(version.version::text, 10, '0') when 'status' then version.status
                 else to_char(version.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.product_versions as version join platform.products as product on product.id = version.product_id
         where (p_search is null or product.sku ilike '%' || p_search || '%') and (p_status is null or version.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'productId', product_id, 'productSku', product_sku, 'version', version, 'status', status, 'publishedAt', published_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  if p_resource = 'prices' then
    if p_sort not in ('createdAt', 'updatedAt', 'status') then
      raise exception using errcode = '22023', message = 'The Price query is invalid';
    end if;
    return (
      with base as (
        select price.id, product.id as product_id, product.sku as product_sku, version.version as product_version, price.currency, price.amount_minor, price.channel,
               price.external_price_id, price.status, price.valid_from, price.valid_until, price.created_at, price.updated_at,
               case p_sort when 'updatedAt' then to_char(price.updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') when 'status' then price.status
                 else to_char(price.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.product_prices as price join platform.product_versions as version on version.id = price.product_version_id
          join platform.products as product on product.id = version.product_id
         where (p_search is null or product.sku ilike '%' || p_search || '%' or price.channel ilike '%' || p_search || '%') and (p_status is null or price.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'productId', product_id, 'productSku', product_sku, 'productVersion', product_version, 'currency', currency, 'amountMinor', amount_minor, 'channel', channel, 'externalPriceId', external_price_id, 'status', status, 'validFrom', valid_from, 'validUntil', valid_until, 'createdAt', created_at, 'updatedAt', updated_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  if p_resource = 'redemption-batches' then
    if p_sort not in ('createdAt', 'name', 'status') then
      raise exception using errcode = '22023', message = 'The Redemption Batch query is invalid';
    end if;
    return (
      with base as (
        select batch.id, batch.name, product.sku as product_sku, version.version as product_version, batch.status, batch.code_prefix, batch.quantity,
               (select count(*)::integer from platform.redemption_codes as code where code.batch_id = batch.id) as issued_count,
               (select count(*)::integer from platform.redemptions as redemption where redemption.batch_id = batch.id) as redeemed_count,
               batch.starts_at, batch.expires_at, batch.created_at,
               case p_sort when 'name' then batch.name when 'status' then batch.status else to_char(batch.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.redemption_batches as batch join platform.products as product on product.id = batch.product_id
          join platform.product_versions as version on version.id = batch.product_version_id
         where (p_search is null or batch.name ilike '%' || p_search || '%' or product.sku ilike '%' || p_search || '%') and (p_status is null or batch.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'productSku', product_sku, 'productVersion', product_version, 'status', status, 'codePrefix', code_prefix, 'quantity', quantity, 'issuedCount', issued_count, 'redeemedCount', redeemed_count, 'startsAt', starts_at, 'expiresAt', expires_at, 'createdAt', created_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  if p_resource = 'redemption-codes' then
    if p_sort not in ('createdAt', 'redeemedAt', 'status') then
      raise exception using errcode = '22023', message = 'The Redemption Code query is invalid';
    end if;
    return (
      with base as (
        select code.id, code.batch_id, code.code_hint, code.status, code.redeemed_at, code.created_at,
               case p_sort when 'redeemedAt' then coalesce(to_char(code.redeemed_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), '') when 'status' then code.status
                 else to_char(code.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.redemption_codes as code join platform.redemption_batches as batch on batch.id = code.batch_id
         where (p_search is null or code.code_hint ilike '%' || p_search || '%' or batch.name ilike '%' || p_search || '%') and (p_status is null or code.status = p_status)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc,
          case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.*
          from base where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id)))
            or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'batchId', batch_id, 'codeHint', code_hint, 'status', status, 'redeemedAt', redeemed_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row)))
    );
  end if;

  raise exception using errcode = '22023', message = 'The Catalog resource is not supported';
end;
$$;


ALTER FUNCTION "public"."admin_query_catalog_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_query_catalog_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") IS 'Returns allowlisted Catalog and Redemption projections without plaintext codes or hashes.';



CREATE OR REPLACE FUNCTION "public"."admin_query_commerce_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 25, "p_search" "text" DEFAULT NULL::"text", "p_status" "text" DEFAULT NULL::"text", "p_sort" "text" DEFAULT 'createdAt'::"text", "p_direction" "text" DEFAULT 'desc'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."admin_query_commerce_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_query_commerce_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") IS 'Returns role-filtered, paginated Order and Payment projections without provider credentials or event payloads.';



CREATE OR REPLACE FUNCTION "public"."admin_query_customer_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 25, "p_search" "text" DEFAULT NULL::"text", "p_status" "text" DEFAULT NULL::"text", "p_sort" "text" DEFAULT 'createdAt'::"text", "p_direction" "text" DEFAULT 'desc'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."admin_query_customer_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_query_customer_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") IS 'Returns the allowlisted Admin Customer resource projection with opaque cursor pagination.';



CREATE OR REPLACE FUNCTION "public"."admin_query_products"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 25, "p_search" "text" DEFAULT NULL::"text", "p_status" "text" DEFAULT NULL::"text", "p_sort" "text" DEFAULT 'createdAt'::"text", "p_direction" "text" DEFAULT 'desc'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."admin_query_products"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_query_products"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") IS 'Returns an explicit Admin Product list projection with current-version summaries.';



CREATE OR REPLACE FUNCTION "public"."admin_query_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 25, "p_search" "text" DEFAULT NULL::"text", "p_status" "text" DEFAULT NULL::"text", "p_sort" "text" DEFAULT 'createdAt'::"text", "p_direction" "text" DEFAULT 'desc'::"text", "p_application_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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
        select feedback.id, feedback.app_id as application_id, app.slug as app_slug, feedback.user_id, feedback.kind, feedback.title,
               case when actor_role in ('owner', 'admin', 'support') then feedback.content else null end as content,
               feedback.status, feedback.created_at,
               case p_sort when 'status' then feedback.status when 'title' then feedback.title else to_char(feedback.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.feedback_requests as feedback
          join platform.platform_apps as app on app.id = feedback.app_id
         where (p_search is null or feedback.title ilike '%' || p_search || '%' or feedback.kind ilike '%' || p_search || '%')
           and (p_status is null or feedback.status = p_status)
           and (p_application_id is null or feedback.app_id = p_application_id)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc, case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.* from base
         where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id))) or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object(
        'items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'applicationId', application_id, 'appSlug', app_slug, 'userId', user_id, 'kind', kind, 'title', title, 'content', content, 'status', status, 'createdAt', created_at) order by row_number) from selected), '[]'::jsonb),
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
        select audit.id, audit.application_id, audit.actor_type, audit.actor_id, audit.action, audit.target_type, audit.target_id,
               audit.request_id, audit.reason, audit.before_summary, audit.after_summary, audit.created_at,
               case p_sort when 'action' then audit.action when 'targetType' then audit.target_type else to_char(audit.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end as sort_value
          from platform.audit_logs as audit
         where (p_search is null or audit.action ilike '%' || p_search || '%' or audit.target_type ilike '%' || p_search || '%')
           and (p_application_id is null or audit.application_id = p_application_id)
      ), filtered as (
        select row_number() over (order by case when p_direction = 'asc' then sort_value end asc, case when p_direction = 'desc' then sort_value end desc, case when p_direction = 'asc' then id end asc, case when p_direction = 'desc' then id end desc) - 1 as row_number, base.* from base
         where cursor_value is null or (p_direction = 'asc' and (sort_value > cursor_value or (sort_value = cursor_value and id > cursor_id))) or (p_direction = 'desc' and (sort_value < cursor_value or (sort_value = cursor_value and id < cursor_id)))
      ), selected as (select * from filtered where row_number < p_limit), next_row as (select * from filtered where row_number = p_limit limit 1)
      select jsonb_build_object(
        'items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'applicationId', application_id, 'actorType', actor_type, 'actorId', actor_id, 'action', action, 'targetType', target_type, 'targetId', target_id, 'requestId', request_id, 'reason', reason, 'beforeSummary', before_summary, 'afterSummary', after_summary, 'createdAt', created_at) order by row_number) from selected), '[]'::jsonb),
        'page', jsonb_build_object('hasMore', exists(select 1 from next_row), 'nextCursor', (select encode(convert_to(jsonb_build_object('value', sort_value, 'id', id)::text, 'utf8'), 'base64') from next_row))
      )
    );
  end if;

  raise exception using errcode = '22023', message = 'The Admin resource is not supported';
end;
$$;


ALTER FUNCTION "public"."admin_query_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text", "p_application_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_query_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text", "p_application_id" "uuid") IS 'Returns allowlisted Admin projections with optional explicit Application filtering.';



CREATE OR REPLACE FUNCTION "public"."admin_redemption_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid" DEFAULT NULL::"uuid", "p_payload" "jsonb" DEFAULT '{}'::"jsonb", "p_reason" "text" DEFAULT NULL::"text", "p_idempotency_key" "text" DEFAULT NULL::"text", "p_request_hash" "text" DEFAULT NULL::"text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $_$
declare
  actor_role text;
  idempotency_row platform.idempotency_records%rowtype;
  batch_row platform.redemption_batches%rowtype;
  version_row platform.product_versions%rowtype;
  product_row platform.products%rowtype;
  code_record jsonb;
  target_id uuid;
  target_type text := 'redemption_batch';
  before_summary jsonb := '{}'::jsonb;
  after_summary jsonb;
  result jsonb;
  audit_id_value uuid;
  requested_quantity integer;
  command_status text;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  if actor_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'Redemption commands require an active Admin member';
  end if;
  if p_action not in ('create_redemption_batch', 'generate_redemption_codes',
                      'pause_redemption_batch', 'close_redemption_batch') then
    raise exception using errcode = '22023', message = 'The Redemption command is not supported';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'The Redemption command payload is invalid';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A Redemption command reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.redemption.command', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.redemption.command'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body;
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The Redemption command is already in progress';
    end if;
  end if;

  if p_action = 'create_redemption_batch' then
    if p_resource_id is not null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in
         ('name', 'productId', 'productVersionId', 'codePrefix', 'quantity', 'perUserLimit', 'startsAt', 'expiresAt', 'source'))
       or p_payload->>'name' is null or btrim(p_payload->>'name') = ''
       or p_payload->>'productId' is null or p_payload->>'productVersionId' is null
       or p_payload->>'codePrefix' !~ '^[A-Z0-9]+(?:-[A-Z0-9]+)*$'
       or p_payload->>'quantity' is null or p_payload->>'source' is null or btrim(p_payload->>'source') = '' then
      raise exception using errcode = '22023', message = 'The Redemption batch fields are invalid';
    end if;
    select product.*
      into product_row
      from platform.products as product
     where product.id = (p_payload->>'productId')::uuid
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product or Product Version was not found';
    end if;
    select version.*
      into version_row
      from platform.product_versions as version
     where version.id = (p_payload->>'productVersionId')::uuid
       and version.product_id = product_row.id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Product or Product Version was not found';
    end if;
    if version_row.status <> 'published' then
      raise exception using errcode = '23514', message = 'Redemption batches require a published Product Version';
    end if;
    insert into platform.redemption_batches
      (name, product_id, product_version_id, code_prefix, quantity, per_user_limit,
       starts_at, expires_at, source, created_by)
    values
      (btrim(p_payload->>'name'), product_row.id, version_row.id, p_payload->>'codePrefix',
       (p_payload->>'quantity')::integer,
       coalesce((p_payload->>'perUserLimit')::integer, 1),
       coalesce((p_payload->>'startsAt')::timestamptz, timezone('utc', now())),
       case when p_payload ? 'expiresAt' then (p_payload->>'expiresAt')::timestamptz else null end,
       btrim(p_payload->>'source'), p_actor_id)
    returning * into batch_row;
    target_id := batch_row.id;
    result := jsonb_build_object(
      'id', batch_row.id, 'name', batch_row.name, 'productSku', product_row.sku,
      'productVersion', version_row.version, 'status', batch_row.status,
      'codePrefix', batch_row.code_prefix, 'quantity', batch_row.quantity,
      'issuedCount', 0, 'redeemedCount', 0, 'startsAt', batch_row.starts_at,
      'expiresAt', batch_row.expires_at, 'createdAt', batch_row.created_at
    );
    after_summary := jsonb_build_object('id', batch_row.id, 'status', batch_row.status,
      'productId', batch_row.product_id, 'productVersionId', batch_row.product_version_id,
      'quantity', batch_row.quantity);
  elsif p_action = 'generate_redemption_codes' then
    if p_resource_id is null
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('quantity', 'codeRecords'))
       or p_payload->>'quantity' is null
       or jsonb_typeof(p_payload->'codeRecords') <> 'array' then
      raise exception using errcode = '22023', message = 'The Redemption code generation fields are invalid';
    end if;
    requested_quantity := (p_payload->>'quantity')::integer;
    if requested_quantity < 1 or requested_quantity > 10000
       or jsonb_array_length(p_payload->'codeRecords') <> requested_quantity then
      raise exception using errcode = '22023', message = 'The Redemption code generation quantity is invalid';
    end if;
    select batch.*
      into batch_row
      from platform.redemption_batches as batch
     where batch.id = p_resource_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Redemption batch was not found';
    end if;
    if batch_row.status <> 'draft' then
      raise exception using errcode = '23514', message = 'Codes can only be generated for a draft batch';
    end if;
    select version.*
      into version_row
      from platform.product_versions as version
     where version.id = batch_row.product_version_id
       and version.product_id = batch_row.product_id
     for update;
    if not found or version_row.status <> 'published' then
      raise exception using errcode = '23514', message = 'Codes require a published Product Version';
    end if;
    if requested_quantity <> batch_row.quantity then
      raise exception using errcode = '22023', message = 'Generation quantity must match the batch quantity';
    end if;
    if exists (select 1 from platform.redemption_codes where batch_id = batch_row.id) then
      raise exception using errcode = '23514', message = 'Redemption codes have already been generated for this batch';
    end if;
    for code_record in select value from jsonb_array_elements(p_payload->'codeRecords') as values(value) loop
      if exists (select 1 from jsonb_object_keys(code_record) as key where key not in ('codeHash', 'codeHint', 'pepperVersion'))
         or code_record->>'codeHash' !~ '^[0-9a-f]{64}$'
         or btrim(coalesce(code_record->>'codeHint', '')) = ''
         or (code_record->>'pepperVersion')::integer < 1 then
        raise exception using errcode = '22023', message = 'A generated Redemption code record is invalid';
      end if;
    end loop;
    insert into platform.redemption_codes (batch_id, code_hash, code_hint, pepper_version)
    select batch_row.id, value->>'codeHash', value->>'codeHint', (value->>'pepperVersion')::smallint
      from jsonb_array_elements(p_payload->'codeRecords') as values(value);
    update platform.redemption_batches set status = 'active' where id = batch_row.id;
    select batch.* into batch_row from platform.redemption_batches as batch where batch.id = p_resource_id;
    target_id := batch_row.id;
    result := jsonb_build_object(
      'batchId', batch_row.id,
      'codes', (select jsonb_agg(jsonb_build_object('codeId', code.id, 'codeHint', code.code_hint)
        order by code.created_at, code.id) from platform.redemption_codes as code where code.batch_id = batch_row.id)
    );
    before_summary := jsonb_build_object('id', batch_row.id, 'status', 'draft', 'quantity', batch_row.quantity);
    after_summary := jsonb_build_object('id', batch_row.id, 'status', batch_row.status,
      'quantity', batch_row.quantity, 'issuedCount', batch_row.quantity);
  elsif p_action = 'pause_redemption_batch' then
    if p_resource_id is null or p_payload <> '{}'::jsonb then
      raise exception using errcode = '22023', message = 'Pause does not accept additional fields';
    end if;
    select batch.* into batch_row from platform.redemption_batches as batch where batch.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Redemption batch was not found'; end if;
    if batch_row.status <> 'active' then
      raise exception using errcode = '23514', message = 'Only active Redemption batches can be paused';
    end if;
    before_summary := jsonb_build_object('id', batch_row.id, 'status', batch_row.status);
    update platform.redemption_batches set status = 'paused' where id = batch_row.id;
    result := jsonb_build_object('batchId', batch_row.id, 'status', 'paused');
    after_summary := jsonb_build_object('id', batch_row.id, 'status', 'paused');
    target_id := batch_row.id;
  elsif p_action = 'close_redemption_batch' then
    if p_resource_id is null or p_payload <> '{}'::jsonb then
      raise exception using errcode = '22023', message = 'Close does not accept additional fields';
    end if;
    select batch.* into batch_row from platform.redemption_batches as batch where batch.id = p_resource_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'The Redemption batch was not found'; end if;
    if batch_row.status not in ('active', 'paused') then
      raise exception using errcode = '23514', message = 'Only active or paused Redemption batches can be closed';
    end if;
    before_summary := jsonb_build_object('id', batch_row.id, 'status', batch_row.status);
    update platform.redemption_batches set status = 'closed' where id = batch_row.id;
    result := jsonb_build_object('batchId', batch_row.id, 'status', 'closed');
    after_summary := jsonb_build_object('id', batch_row.id, 'status', 'closed');
    target_id := batch_row.id;
  end if;

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('admin', p_actor_id, 'redemption.' || p_action, target_type, target_id, p_request_id, p_reason,
     before_summary, coalesce(after_summary, '{}'::jsonb))
  returning id into audit_id_value;
  result := result || jsonb_build_object('auditLogId', audit_id_value);
  update platform.idempotency_records
     set status = 'completed', resource_type = target_type, resource_id = target_id,
         response_status = 200, response_body = result
   where id = idempotency_row.id;
  return result;
end;
$_$;


ALTER FUNCTION "public"."admin_redemption_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_redemption_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") IS 'Executes explicit audited Redemption batch lifecycle and code generation commands without storing plaintext.';



CREATE OR REPLACE FUNCTION "public"."admin_refund_order_item"("p_actor_id" "uuid", "p_order_item_id" "uuid", "p_amount" bigint, "p_mode" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."admin_refund_order_item"("p_actor_id" "uuid", "p_order_item_id" "uuid", "p_amount" bigint, "p_mode" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_refund_order_item"("p_actor_id" "uuid", "p_order_item_id" "uuid", "p_amount" bigint, "p_mode" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") IS 'Runs an idempotent Admin OrderItem refund command with role enforcement and append-only audit.';



CREATE OR REPLACE FUNCTION "public"."admin_user_overview"("p_actor_id" "uuid", "p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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
    ), '[]'::jsonb),'deletionRequests', coalesce((
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


ALTER FUNCTION "public"."admin_user_overview"("p_actor_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_user_overview"("p_actor_id" "uuid", "p_user_id" "uuid") IS 'Returns one role-filtered User 360 aggregate without exposing sessions, tokens, IPs, or database tables.';



CREATE OR REPLACE FUNCTION "public"."admin_verify_order"("p_actor_id" "uuid", "p_order_id" "uuid", "p_payment_reference" "text", "p_amount" bigint, "p_currency" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $_$
declare
  actor_role text;
  idempotency_row platform.idempotency_records%rowtype;
  order_row platform.orders%rowtype;
  payment_row platform.payments%rowtype;
  fulfillment_result jsonb;
  fulfillment_audit_id uuid;
  audit_id_value uuid;
  event_id_value uuid := gen_random_uuid();
  now_value timestamptz := timezone('utc', now());
  external_event_id_value text := 'manual-' || replace(p_request_id::text, '-', '');
  result jsonb;
begin
  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';

  if actor_role is null or actor_role not in ('owner', 'finance') then
    raise exception using errcode = '42501', message = 'Manual order verification requires Finance or Owner access';
  end if;
  if p_order_id is null or p_actor_id is null or p_request_id is null then
    raise exception using errcode = '22023', message = 'Manual order verification identity is invalid';
  end if;
  if p_payment_reference is null
     or btrim(p_payment_reference) = ''
     or length(p_payment_reference) > 200
     or p_payment_reference ~ '[[:space:]]'
     or p_amount is null
     or p_amount < 0
     or p_currency is null
     or p_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'Manual payment evidence is invalid';
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A manual verification reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('admin.order.verify', 'admin:' || p_actor_id::text, p_idempotency_key, p_request_hash,
     now_value + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'admin.order.verify'
       and record.actor_key = 'admin:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body || jsonb_build_object('idempotent', true);
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The manual verification is already in progress';
    end if;
  end if;

  select order_fact.*
    into order_row
    from platform.orders as order_fact
   where order_fact.id = p_order_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The order was not found';
  end if;
  if order_row.channel <> 'manual' or order_row.status <> 'pending' then
    raise exception using errcode = 'P0004', message = 'The order is not eligible for manual verification';
  end if;

  select payment.*
    into payment_row
    from platform.payments as payment
   where payment.order_id = order_row.id
     and payment.status = 'pending'
   order by payment.created_at, payment.id
   limit 1
   for update;
  if not found then
    raise exception using errcode = 'P0006', message = 'A pending payment was not found for the order';
  end if;
  if payment_row.provider <> 'manual'
     or payment_row.external_payment_id is distinct from p_payment_reference then
    raise exception using errcode = 'P0005', message = 'The manual payment reference does not match the order payment';
  end if;
  if payment_row.amount <> p_amount or payment_row.currency <> p_currency
     or order_row.amount_total <> p_amount or order_row.currency <> p_currency then
    raise exception using errcode = 'P0003', message = 'The manual payment amount or currency does not match the order';
  end if;

  insert into platform.payment_events
    (id, payment_id, order_id, provider, external_event_id, event_type, status,
     currency, amount, payload_summary, occurred_at, created_at, updated_at)
  values
    (event_id_value, payment_row.id, order_row.id, 'manual', external_event_id_value,
     'payment.succeeded', 'received', p_currency, p_amount,
     jsonb_build_object(
       'channel', 'manual',
       'paymentReference', p_payment_reference,
       'amountMinor', p_amount,
       'currency', p_currency
     ),
     now_value, now_value, now_value);

  select public.fulfill_paid_order(event_id_value)
    into fulfillment_result;

  select audit.id
    into fulfillment_audit_id
    from platform.audit_logs as audit
   where audit.action = 'commerce.fulfill_paid_order'
     and audit.target_type = 'order'
     and audit.target_id = order_row.id
     and audit.request_id = event_id_value
   order by audit.created_at desc, audit.id desc
   limit 1;
  if fulfillment_audit_id is null then
    raise exception using errcode = 'P0007', message = 'The fulfillment audit record was not created';
  end if;

  result := jsonb_build_object(
    'orderId', order_row.id,
    'paymentId', payment_row.id,
    'paymentEventId', event_id_value,
    'status', 'fulfilled',
    'grantIds', coalesce(fulfillment_result->'grantIds', '[]'::jsonb),
    'idempotent', false,
    'fulfillmentAuditLogId', fulfillment_audit_id,
    'overviewPath', '/v1/admin/orders/' || order_row.id::text || '/overview'
  );

  insert into platform.audit_logs
    (actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    ('admin', p_actor_id, 'orders.verify', 'order', order_row.id, p_request_id, p_reason,
     jsonb_build_object('orderStatus', 'pending', 'paymentStatus', 'pending', 'channel', order_row.channel),
     jsonb_build_object('orderStatus', 'fulfilled', 'paymentStatus', 'succeeded',
                        'paymentEventId', event_id_value, 'fulfillmentAuditLogId', fulfillment_audit_id))
  returning id into audit_id_value;

  result := result || jsonb_build_object(
    'auditLogId', audit_id_value,
    'auditPath', '/v1/admin/audit-logs/' || audit_id_value::text
  );

  update platform.idempotency_records
     set status = 'completed',
         resource_type = 'order',
         resource_id = order_row.id,
         response_status = 200,
         response_body = result
   where id = idempotency_row.id;
  return result;
end;
$_$;


ALTER FUNCTION "public"."admin_verify_order"("p_actor_id" "uuid", "p_order_id" "uuid", "p_payment_reference" "text", "p_amount" bigint, "p_currency" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_verify_order"("p_actor_id" "uuid", "p_order_id" "uuid", "p_payment_reference" "text", "p_amount" bigint, "p_currency" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") IS 'Verifies a manual payment as an audited Admin command and delegates fulfillment to the shared atomic domain function.';



CREATE OR REPLACE FUNCTION "public"."application_membership_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid" DEFAULT NULL::"uuid", "p_user_id" "uuid" DEFAULT NULL::"uuid", "p_membership_id" "uuid" DEFAULT NULL::"uuid", "p_created_source" "text" DEFAULT 'system'::"text", "p_reason" "text" DEFAULT NULL::"text", "p_idempotency_key" "text" DEFAULT NULL::"text", "p_request_hash" "text" DEFAULT NULL::"text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  actor_role text;
  membership_row platform.application_memberships%rowtype;
  app_row platform.platform_apps%rowtype;
  idempotency_row platform.idempotency_records%rowtype;
  audit_id uuid := gen_random_uuid();
  before_summary jsonb := '{}'::jsonb;
  after_summary jsonb;
  result jsonb;
  is_admin boolean;
  target_user_id uuid;
  target_application_id uuid;
begin
  if p_actor_id is null or p_action is null or btrim(p_action) = '' then
    raise exception using errcode = '22023', message = 'Membership command actor and action are required';
  end if;
  if p_request_id is null then
    p_request_id := gen_random_uuid();
  end if;
  if p_reason is null or btrim(p_reason) = '' or length(p_reason) > 1000 then
    raise exception using errcode = '22023', message = 'A Membership command reason is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' or length(p_idempotency_key) > 255
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'An idempotency key and request hash are required';
  end if;

  select member.role
    into actor_role
    from platform.admin_members as member
   where member.user_id = p_actor_id
     and member.status = 'active';
  is_admin := coalesce(actor_role in ('owner', 'admin', 'support'), false);

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('application.membership.command', 'user:' || p_actor_id::text, p_idempotency_key,
     p_request_hash, timezone('utc', now()) + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'application.membership.command'
       and record.actor_key = 'user:' || p_actor_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' and idempotency_row.response_body is not null then
      return idempotency_row.response_body;
    end if;
    if idempotency_row.status = 'in_progress' then
      raise exception using errcode = '40001', message = 'The Membership command is already in progress';
    end if;
  end if;

  if p_action = 'create' then
    if p_application_id is null or p_user_id is null or p_membership_id is not null then
      raise exception using errcode = '22023', message = 'Membership creation fields are invalid';
    end if;
    if p_user_id <> p_actor_id and not is_admin then
      raise exception using errcode = '42501', message = 'Only an Admin can create membership for another user';
    end if;
    select app.* into app_row
      from platform.platform_apps as app
     where app.id = p_application_id and app.status = 'active'
     for share;
    if not found then
      raise exception using errcode = 'P0002', message = 'The active Application was not found';
    end if;
    if p_created_source is null or btrim(p_created_source) = '' or length(p_created_source) > 100 then
      raise exception using errcode = '22023', message = 'Membership creation source is invalid';
    end if;
    insert into platform.application_memberships
      (id, application_id, user_id, status, created_source, activated_at, created_by)
    values
      (gen_random_uuid(), p_application_id, p_user_id,
       case when app_row.membership_policy = 'create_on_first_authorization' then 'active' else 'pending' end,
       btrim(p_created_source),
       case when app_row.membership_policy = 'create_on_first_authorization' then timezone('utc', now()) else null end,
       p_actor_id)
    returning * into membership_row;
  else
    if p_membership_id is null then
      raise exception using errcode = '22023', message = 'Membership id is required';
    end if;
    select membership.* into membership_row
      from platform.application_memberships as membership
     where membership.id = p_membership_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The Application membership was not found';
    end if;
    before_summary := jsonb_build_object(
      'id', membership_row.id,
      'applicationId', membership_row.application_id,
      'userId', membership_row.user_id,
      'status', membership_row.status
    );
    target_user_id := membership_row.user_id;
    target_application_id := membership_row.application_id;
    if p_actor_id <> target_user_id and not is_admin then
      raise exception using errcode = '42501', message = 'Membership management requires the member or an Admin';
    end if;
    if p_action = 'activate' then
      if p_actor_id <> target_user_id and not is_admin then
        raise exception using errcode = '42501', message = 'Only the member or an Admin can activate membership';
      end if;
      if membership_row.status <> 'pending' then
        raise exception using errcode = '23514', message = 'Only pending membership can be activated';
      end if;
      update platform.application_memberships
         set status = 'active', activated_at = timezone('utc', now()),
             suspended_at = null, suspended_reason = null
       where id = membership_row.id;
    elsif p_action = 'suspend' then
      if not is_admin then
        raise exception using errcode = '42501', message = 'Only an Admin can suspend membership';
      end if;
      if membership_row.status <> 'active' then
        raise exception using errcode = '23514', message = 'Only active membership can be suspended';
      end if;
      update platform.application_memberships
         set status = 'suspended', suspended_at = timezone('utc', now()), suspended_reason = btrim(p_reason)
       where id = membership_row.id;
    elsif p_action = 'restore' then
      if not is_admin then
        raise exception using errcode = '42501', message = 'Only an Admin can restore membership';
      end if;
      if membership_row.status <> 'suspended' then
        raise exception using errcode = '23514', message = 'Only suspended membership can be restored';
      end if;
      update platform.application_memberships
         set status = 'active', activated_at = coalesce(activated_at, timezone('utc', now())),
             suspended_at = null, suspended_reason = null
       where id = membership_row.id;
    elsif p_action = 'leave' then
      if membership_row.status not in ('pending', 'active', 'suspended') then
        raise exception using errcode = '23514', message = 'Only current membership can be left';
      end if;
      update platform.application_memberships
         set status = 'left', left_at = timezone('utc', now()),
             suspended_at = null, suspended_reason = null
       where id = membership_row.id;
    elsif p_action = 'delete' then
      if not is_admin then
        raise exception using errcode = '42501', message = 'Only an Admin can delete membership';
      end if;
      if membership_row.status not in ('left', 'suspended') then
        raise exception using errcode = '23514', message = 'Only left or suspended membership can be deleted';
      end if;
      update platform.application_memberships
         set status = 'deleted', deleted_at = timezone('utc', now()),
             suspended_at = null, suspended_reason = null
       where id = membership_row.id;
    else
      raise exception using errcode = '22023', message = 'The Membership command is not supported';
    end if;
    select membership.* into membership_row
      from platform.application_memberships as membership
     where membership.id = p_membership_id;
    if p_action = 'leave' then
      perform platform.cleanup_application_data(membership_row.id);
    end if;
  end if;

  before_summary := case when p_action = 'create' then '{}'::jsonb else before_summary end;
  after_summary := jsonb_build_object(
    'id', membership_row.id,
    'applicationId', membership_row.application_id,
    'userId', membership_row.user_id,
    'status', membership_row.status,
    'createdSource', membership_row.created_source
  );
  result := jsonb_build_object(
    'id', membership_row.id,
    'applicationId', membership_row.application_id,
    'userId', membership_row.user_id,
    'status', membership_row.status,
    'createdSource', membership_row.created_source,
    'joinedAt', membership_row.joined_at,
    'activatedAt', membership_row.activated_at,
    'suspendedAt', membership_row.suspended_at,
    'leftAt', membership_row.left_at,
    'deletedAt', membership_row.deleted_at,
    'auditLogId', audit_id
  );

  if target_application_id is not null then
    perform set_config('app.application_id', target_application_id::text, true);
  end if;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason,
     before_summary, after_summary)
  values
    (audit_id, case when is_admin then 'admin' else 'user' end, p_actor_id,
     'applications.membership.' || p_action, 'application_membership', membership_row.id,
     p_request_id, btrim(p_reason), before_summary, after_summary);

  update platform.idempotency_records
     set status = 'completed', resource_type = 'application_membership', resource_id = membership_row.id,
         response_status = 200, response_body = result
   where id = idempotency_row.id;
  return result;
end;
$$;


ALTER FUNCTION "public"."application_membership_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_created_source" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."application_membership_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_created_source" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") IS 'Executes application membership lifecycle transitions without changing Global Profile state.';



CREATE OR REPLACE FUNCTION "public"."cancel_account_deletion"("p_user_id" "uuid", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("deletion_request_id" "uuid", "status" "text", "execute_after" timestamp with time zone, "requested_at" timestamp with time zone, "completed_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  request_row platform.account_deletion_requests%rowtype;
  latest_row platform.account_deletion_requests%rowtype;
  now_value timestamptz := timezone('utc', now());
  audit_id_value uuid := gen_random_uuid();
begin
  if p_user_id is null then
    raise exception using errcode = '22023', message = 'A user is required';
  end if;

  select request_item.*
    into latest_row
    from platform.account_deletion_requests as request_item
   where request_item.user_id = p_user_id
     and request_item.status in ('pending', 'processing', 'failed')
   order by request_item.requested_at desc, request_item.id desc
   limit 1
   for update;

  if not found then
    select request_item.*
      into latest_row
      from platform.account_deletion_requests as request_item
     where request_item.user_id = p_user_id
     order by request_item.requested_at desc, request_item.id desc
     limit 1
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The account deletion request was not found';
    end if;
  end if;

  if latest_row.status = 'cancelled' then
    return query select latest_row.id, latest_row.status, latest_row.execute_after,
                        latest_row.requested_at, latest_row.completed_at;
    return;
  end if;
  if latest_row.status not in ('pending', 'failed') then
    raise exception using errcode = '23514', message = 'The account deletion request cannot be cancelled in its current state';
  end if;

  update platform.account_deletion_requests
     set status = 'cancelled',
         cancelled_at = now_value,
         next_attempt_at = null,
         last_error_code = null
   where id = latest_row.id
  returning * into request_row;

  update platform.profiles
     set status = 'active'
   where id = p_user_id
     and platform.profiles.status = 'deletion_pending';

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'user', p_user_id, 'account.deletion.cancelled', 'account_deletion_request',
     request_row.id, p_request_id, 'User cancelled account deletion',
     jsonb_build_object('status', latest_row.status),
     jsonb_build_object('status', request_row.status));

  return query
  select request_row.id, request_row.status, request_row.execute_after,
         request_row.requested_at, request_row.completed_at;
end;
$$;


ALTER FUNCTION "public"."cancel_account_deletion"("p_user_id" "uuid", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cancel_account_deletion"("p_user_id" "uuid", "p_request_id" "uuid") IS 'Cancels a pending or failed deletion request and restores the profile to active without restoring sessions or entitlements.';



CREATE OR REPLACE FUNCTION "public"."chargeback_order"("p_order_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."chargeback_order"("p_order_id" "uuid", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."chargeback_order"("p_order_id" "uuid", "p_reason" "text") IS 'Atomically marks an eligible Order as chargeback, disputes its payment, revokes all active OrderItem grants, and audits the outcome.';



CREATE OR REPLACE FUNCTION "public"."check_access"("p_user_id" "uuid", "p_app_slug" "text", "p_feature_code" "text") RETURNS TABLE("allowed" boolean, "feature" "text", "value" "jsonb", "source_product" "text", "expires_at" timestamp with time zone, "decision_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  app_row record;
  feature_row record;
  contribution_count bigint;
  bool_value boolean;
  sum_value numeric;
  max_value numeric;
  min_value numeric;
  latest_value jsonb;
  source_product_value text;
  expiry_value timestamptz;
  resolved_value jsonb;
begin
  if p_user_id is null or p_app_slug is null or p_feature_code is null then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;

  select app.id, app.primary_feature_id
    into app_row
    from platform.platform_apps as app
   where app.slug = p_app_slug
     and app.status = 'active';

  if not found then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;

  select feature.id, feature.app_id, feature.value_type, feature.merge_strategy
    into feature_row
    from platform.features as feature
   where feature.code = p_feature_code
     and (feature.app_id is null or feature.app_id = app_row.id);

  if not found then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;

  with contributions as (
    select grants.id as grant_id,
           grants.expires_at,
           grants.created_at,
           products.sku,
           snapshots.value
      from platform.entitlement_grants as grants
      join platform.product_version_features as snapshots
        on snapshots.product_version_id = grants.product_version_id
      join platform.features as source_features
        on source_features.id = snapshots.feature_id
      join platform.products as products
        on products.id = grants.product_id
     where grants.user_id = p_user_id
       and grants.status = 'active'
       and grants.starts_at <= timezone('utc', now())
       and (grants.expires_at is null or grants.expires_at > timezone('utc', now()))
       and (
         source_features.id = feature_row.id
         or (
           feature_row.id = app_row.primary_feature_id
           and source_features.code = 'hub.all_apps_access'
           and source_features.app_id is null
           and snapshots.value = 'true'::jsonb
         )
       )
  )
  select count(*),
         bool_or(case when feature_row.merge_strategy = 'any_true' then (contributions.value #>> '{}')::boolean end),
         sum(case when feature_row.merge_strategy = 'sum' then (contributions.value #>> '{}')::numeric end),
         max(case when feature_row.merge_strategy in ('max', 'latest') and feature_row.value_type = 'integer' then (contributions.value #>> '{}')::numeric end),
         min(case when feature_row.merge_strategy = 'min' then (contributions.value #>> '{}')::numeric end),
         (array_agg(contributions.value order by contributions.created_at desc, contributions.grant_id desc))[1],
         string_agg(distinct sku, ',' order by sku),
         min(contributions.expires_at)
    into contribution_count, bool_value, sum_value, max_value, min_value,
         latest_value, source_product_value, expiry_value
    from contributions;

  if contribution_count = 0 then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;

  case feature_row.merge_strategy
    when 'any_true' then resolved_value := to_jsonb(coalesce(bool_value, false));
    when 'sum' then resolved_value := to_jsonb(sum_value);
    when 'max' then resolved_value := to_jsonb(max_value);
    when 'min' then resolved_value := to_jsonb(min_value);
    when 'latest' then resolved_value := latest_value;
    else
      raise exception using
        errcode = '23514',
        message = 'Unsupported entitlement merge strategy';
  end case;

  return query
  select true, p_feature_code, resolved_value, source_product_value, expiry_value, gen_random_uuid();
end;
$$;


ALTER FUNCTION "public"."check_access"("p_user_id" "uuid", "p_app_slug" "text", "p_feature_code" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."check_access"("p_user_id" "uuid", "p_app_slug" "text", "p_feature_code" "text") IS 'Resolves all active nonexpired snapshot grants on the server with deterministic feature merging.';



CREATE OR REPLACE FUNCTION "public"."check_application_access"("p_user_id" "uuid", "p_application_id" "uuid", "p_feature_code" "text") RETURNS TABLE("allowed" boolean, "feature" "text", "value" "jsonb", "source_product" "text", "expires_at" timestamp with time zone, "decision_id" "uuid")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  app_slug text;
begin
  if p_user_id is null or p_application_id is null or p_feature_code is null then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;
  if not exists (
    select 1
      from platform.application_memberships as membership
     where membership.application_id = p_application_id
       and membership.user_id = p_user_id
       and membership.status = 'active'
  ) then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;
  select app.slug into app_slug
    from platform.platform_apps as app
   where app.id = p_application_id
     and app.status = 'active';
  if app_slug is null then
    return query select false, p_feature_code, null::jsonb, null::text, null::timestamptz, gen_random_uuid();
    return;
  end if;
  return query select access.allowed, access.feature, access.value, access.source_product,
                      access.expires_at, access.decision_id
                 from public.check_access(p_user_id, app_slug, p_feature_code) as access;
end;
$$;


ALTER FUNCTION "public"."check_application_access"("p_user_id" "uuid", "p_application_id" "uuid", "p_feature_code" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."check_application_access"("p_user_id" "uuid", "p_application_id" "uuid", "p_feature_code" "text") IS 'Resolves access only after verifying an active Application Membership.';



CREATE OR REPLACE FUNCTION "public"."claim_account_deletion_request"("p_worker_id" "uuid") RETURNS TABLE("deletion_request_id" "uuid", "user_id" "uuid", "status" "text", "attempt_count" integer, "execute_after" timestamp with time zone, "processing_started_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  request_row platform.account_deletion_requests%rowtype;
  now_value timestamptz := timezone('utc', now());
begin
  if p_worker_id is null then
    raise exception using errcode = '22023', message = 'A worker ID is required';
  end if;

  select request_item.*
    into request_row
    from platform.account_deletion_requests as request_item
   where request_item.status in ('pending', 'failed')
     and request_item.execute_after <= now_value
     and (request_item.next_attempt_at is null or request_item.next_attempt_at <= now_value)
   order by request_item.execute_after, request_item.requested_at, request_item.id
   limit 1
   for update skip locked;

  if not found then
    return;
  end if;

  update platform.account_deletion_requests
     set status = 'processing',
         attempt_count = request_row.attempt_count + 1,
         last_error_code = null,
         next_attempt_at = null,
         worker_id = p_worker_id,
         processing_started_at = now_value
   where id = request_row.id
  returning * into request_row;

  return query
  select request_row.id, request_row.user_id, request_row.status,
         request_row.attempt_count, request_row.execute_after,
         request_row.processing_started_at;
end;
$$;


ALTER FUNCTION "public"."claim_account_deletion_request"("p_worker_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."claim_account_deletion_request"("p_worker_id" "uuid") IS 'Claims one due pending/failed request with a row lock for a later cross-system worker.';



CREATE OR REPLACE FUNCTION "public"."complete_account_deletion_request"("p_deletion_request_id" "uuid", "p_worker_id" "uuid", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  request_row platform.account_deletion_requests%rowtype;
  profile_row platform.profiles%rowtype;
  grant_row record;
  membership_row record;
  cleaned_membership_count integer := 0;
  now_value timestamptz := timezone('utc', now());
  audit_id_value uuid := gen_random_uuid();
  revoked_grant_count integer := 0;
  anonymized_feedback_count integer := 0;
  detached_order_count integer := 0;
  disabled_admin_count integer := 0;
  result jsonb;
begin
  if p_deletion_request_id is null or p_worker_id is null then
    raise exception using errcode = '22023', message = 'A deletion request and worker are required';
  end if;
  select request_item.* into request_row
    from platform.account_deletion_requests as request_item
   where request_item.id = p_deletion_request_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The account deletion request was not found';
  end if;
  if request_row.status = 'completed' then
    return jsonb_build_object('deletionRequestId', request_row.id, 'userId', request_row.user_id,
      'status', request_row.status, 'completedAt', request_row.completed_at, 'idempotent', true);
  end if;
  if request_row.status <> 'processing' or request_row.worker_id is distinct from p_worker_id then
    raise exception using errcode = '42501', message = 'The worker does not own the processing request';
  end if;
  select profile_item.* into profile_row
    from platform.profiles as profile_item
   where profile_item.id = request_row.user_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The account profile was not found';
  end if;

  for membership_row in
    select membership.id from platform.application_memberships as membership
     where membership.user_id = request_row.user_id
       and membership.status <> 'deleted'
     order by membership.id for update
  loop
    perform platform.cleanup_application_data(membership_row.id);
    update platform.application_memberships
       set status = 'deleted', deleted_at = coalesce(deleted_at, now_value),
           left_at = coalesce(left_at, now_value), suspended_at = null, suspended_reason = null
     where id = membership_row.id;
    cleaned_membership_count := cleaned_membership_count + 1;
  end loop;

  for grant_row in
    select grant_item.id from platform.entitlement_grants as grant_item
     where grant_item.user_id = request_row.user_id and grant_item.status = 'active'
     order by grant_item.id for update
  loop
    perform public.revoke_entitlement(grant_row.id, 'system', null,
      'Account deletion de-identification', p_request_id);
    revoked_grant_count := revoked_grant_count + 1;
  end loop;

  update platform.feedback_requests
     set user_id = null, title = '[deleted]', content = '[deleted]'
   where user_id = request_row.user_id;
  get diagnostics anonymized_feedback_count = row_count;
  update platform.orders set user_id = null where user_id = request_row.user_id;
  get diagnostics detached_order_count = row_count;
  update platform.admin_members
     set status = 'disabled', disabled_at = coalesce(disabled_at, now_value),
         created_by = case when created_by = request_row.user_id then null else created_by end
   where user_id = request_row.user_id and status = 'active';
  get diagnostics disabled_admin_count = row_count;

  perform set_config('app.audit_scrub', 'account_deletion', true);
  update platform.audit_logs set ip_hash = null
   where actor_id = request_row.user_id or (target_type = 'user' and target_id = request_row.user_id);
  perform set_config('app.audit_scrub', '', true);
  update platform.profiles
     set display_name = null, avatar_url = null, locale = null,
         status = 'deleted', deleted_at = coalesce(deleted_at, now_value)
   where id = request_row.user_id;
  update platform.account_deletion_requests
     set status = 'completed', completed_at = coalesce(completed_at, now_value),
         worker_id = null, processing_started_at = null, next_attempt_at = null, last_error_code = null
   where id = request_row.id returning * into request_row;

  result := jsonb_build_object('deletionRequestId', request_row.id, 'userId', request_row.user_id,
    'status', request_row.status, 'completedAt', request_row.completed_at,
    'revokedGrantCount', revoked_grant_count, 'anonymizedFeedbackCount', anonymized_feedback_count,
    'detachedOrderCount', detached_order_count, 'disabledAdminCount', disabled_admin_count,
    'idempotent', false);
  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'system', null, 'account.deletion.completed', 'account_deletion_request', request_row.id,
     p_request_id, 'Account deletion and de-identification completed',
     jsonb_build_object('profileStatus', profile_row.status, 'requestStatus', 'processing'), result);
  return result;
end;
$$;


ALTER FUNCTION "public"."complete_account_deletion_request"("p_deletion_request_id" "uuid", "p_worker_id" "uuid", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."complete_account_deletion_request"("p_deletion_request_id" "uuid", "p_worker_id" "uuid", "p_request_id" "uuid") IS 'Completes one worker-owned deletion transaction after Auth anonymization, preserving financial facts and making the operation idempotent.';



CREATE OR REPLACE FUNCTION "public"."create_application_feedback"("p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_kind" "text", "p_title" "text", "p_content" "text") RETURNS TABLE("id" "uuid", "status" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."create_application_feedback"("p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_kind" "text", "p_title" "text", "p_content" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."create_application_feedback"("p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_kind" "text", "p_title" "text", "p_content" "text") IS 'Creates authenticated feedback from the server-resolved Application and Membership context.';



CREATE OR REPLACE FUNCTION "public"."current_profile"() RETURNS TABLE("id" "uuid", "display_name" "text", "avatar_url" "text", "locale" "text", "status" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'auth', 'platform'
    AS $$
  select
    profiles.id,
    profiles.display_name,
    profiles.avatar_url,
    profiles.locale,
    profiles.status,
    profiles.created_at,
    profiles.updated_at
  from platform.profiles
  where auth.uid() is not null
    and profiles.id = auth.uid();
$$;


ALTER FUNCTION "public"."current_profile"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."current_profile"() IS 'Authenticated user-scoped profile projection; never exposes another user or profile deletion metadata.';



CREATE OR REPLACE FUNCTION "public"."fail_account_deletion_request"("p_request_id" "uuid", "p_worker_id" "uuid", "p_error_code" "text") RETURNS TABLE("deletion_request_id" "uuid", "status" "text", "attempt_count" integer, "next_attempt_at" timestamp with time zone, "last_error_code" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  request_row platform.account_deletion_requests%rowtype;
  now_value timestamptz := timezone('utc', now());
begin
  if p_request_id is null or p_worker_id is null or p_error_code is null
     or p_error_code not in ('AUTH_USER_UPDATE_FAILED', 'AUTH_USER_NOT_FOUND', 'DATABASE_STEP_FAILED', 'RETRYABLE_EXTERNAL_ERROR') then
    raise exception using errcode = '22023', message = 'A request, worker, and stable error code are required';
  end if;

  select request_item.*
    into request_row
    from platform.account_deletion_requests as request_item
   where request_item.id = p_request_id
   for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The account deletion request was not found';
  end if;
  if request_row.status <> 'processing' or request_row.worker_id is distinct from p_worker_id then
    raise exception using errcode = '42501', message = 'The worker does not own the processing request';
  end if;

  update platform.account_deletion_requests
     set status = 'failed',
         last_error_code = p_error_code,
         next_attempt_at = now_value + interval '5 minutes',
         worker_id = null,
         processing_started_at = null
   where id = request_row.id
  returning * into request_row;

  return query
  select request_row.id, request_row.status, request_row.attempt_count,
         request_row.next_attempt_at, request_row.last_error_code;
end;
$$;


ALTER FUNCTION "public"."fail_account_deletion_request"("p_request_id" "uuid", "p_worker_id" "uuid", "p_error_code" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."fail_account_deletion_request"("p_request_id" "uuid", "p_worker_id" "uuid", "p_error_code" "text") IS 'Records only a stable retryable failure code for a worker-owned deletion request.';



CREATE OR REPLACE FUNCTION "public"."fulfill_paid_order"("p_payment_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."fulfill_paid_order"("p_payment_event_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."fulfill_paid_order"("p_payment_event_id" "uuid") IS 'Atomically fulfills a pending order from one payment success event, granting each OrderItem independently and safely replaying processed events.';



CREATE OR REPLACE FUNCTION "public"."get_public_app"("app_slug" "text") RETURNS TABLE("slug" "text", "name" "text", "category" "text", "status" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $_$
  select
    apps.slug,
    apps.name,
    apps.category,
    apps.status
  from platform.platform_apps as apps
  where apps.slug = $1
    and apps.status = 'active';
$_$;


ALTER FUNCTION "public"."get_public_app"("app_slug" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_public_app"("app_slug" "text") IS 'Returns the minimal active application identity for public API reads.';



CREATE OR REPLACE FUNCTION "public"."get_public_products"() RETURNS TABLE("sku" "text", "name" "text", "billing_type" "text", "version" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
  select product.sku, product.name, product.billing_type, version.version
    from platform.products as product
    join platform.product_versions as version
      on version.id = product.current_version_id
     and version.product_id = product.id
   where product.status = 'active'
     and version.status = 'published'
   order by product.sku;
$$;


ALTER FUNCTION "public"."get_public_products"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_public_products"() IS 'Returns only active products and their current published version for the public catalog.';



CREATE OR REPLACE FUNCTION "public"."grant_entitlement"("p_user_id" "uuid", "p_product_version_id" "uuid", "p_source_type" "text", "p_source_id" "uuid" DEFAULT NULL::"uuid", "p_starts_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()), "p_expires_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_actor_type" "text" DEFAULT 'system'::"text", "p_actor_id" "uuid" DEFAULT NULL::"uuid", "p_reason" "text" DEFAULT NULL::"text", "p_restores_grant_id" "uuid" DEFAULT NULL::"uuid", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("grant_id" "uuid", "source_id" "uuid", "status" "text", "starts_at" timestamp with time zone, "expires_at" timestamp with time zone, "audit_log_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  version_row platform.product_versions%rowtype;
  grant_id_value uuid := gen_random_uuid();
  audit_id_value uuid := gen_random_uuid();
  effective_source_id uuid;
begin
  if p_reason is null or btrim(p_reason) = '' then
    raise exception using
      errcode = '23514',
      message = 'An entitlement grant reason is required';
  end if;

  if p_actor_type not in ('admin', 'system', 'user', 'webhook') then
    raise exception using
      errcode = '23514',
      message = 'Invalid audit actor type';
  end if;

  select version.*
    into version_row
    from platform.product_versions as version
   where version.id = p_product_version_id
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Product version was not found';
  end if;

  if version_row.status <> 'published' then
    raise exception using
      errcode = '23514',
      message = 'Entitlements must reference a published product version';
  end if;

  if p_source_type in ('admin', 'admin_restore') then
    if p_actor_type <> 'admin' or p_actor_id is null then
      raise exception using
        errcode = '42501',
        message = 'Admin entitlement grants require an admin actor';
    end if;
    if p_source_id is not null then
      raise exception using
        errcode = '23514',
        message = 'Admin grant source IDs are generated from audit IDs';
    end if;
    effective_source_id := audit_id_value;
  else
    if p_source_id is null then
      raise exception using
        errcode = '23514',
        message = 'Non-admin entitlement grants require a source ID';
    end if;
    if p_restores_grant_id is not null then
      raise exception using
        errcode = '23514',
        message = 'Only admin restore grants may link an original grant';
    end if;
    effective_source_id := p_source_id;
  end if;

  if p_source_type = 'admin' and p_restores_grant_id is not null then
    raise exception using
      errcode = '23514',
      message = 'Ordinary admin grants cannot restore an original grant';
  end if;

  if p_source_type = 'admin_restore'
     and exists (
       select 1
       from platform.entitlement_restore_links as link
       where link.restores_grant_id = p_restores_grant_id
     ) then
    raise exception using
      errcode = '23505',
      message = 'The original entitlement has already been restored';
  end if;

  insert into platform.entitlement_grants
    (id, user_id, product_id, product_version_id, source_type, source_id,
     starts_at, expires_at, restores_grant_id)
  values
    (grant_id_value, p_user_id, version_row.product_id, version_row.id, p_source_type, effective_source_id,
     p_starts_at, p_expires_at, p_restores_grant_id);

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, p_actor_type, p_actor_id, 'entitlements.grant', 'entitlement_grant', grant_id_value,
     p_request_id, p_reason, '{}'::jsonb,
     jsonb_build_object(
       'grantId', grant_id_value,
       'productVersionId', version_row.id,
       'sourceType', p_source_type,
       'status', 'active'
     ));

  if p_source_type = 'admin_restore' then
    insert into platform.entitlement_restore_links (restores_grant_id, restored_grant_id)
    values (p_restores_grant_id, grant_id_value);
  end if;

  return query
  select grant_id_value, effective_source_id, 'active', p_starts_at, p_expires_at, audit_id_value;
end;
$$;


ALTER FUNCTION "public"."grant_entitlement"("p_user_id" "uuid", "p_product_version_id" "uuid", "p_source_type" "text", "p_source_id" "uuid", "p_starts_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_actor_type" "text", "p_actor_id" "uuid", "p_reason" "text", "p_restores_grant_id" "uuid", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."grant_entitlement"("p_user_id" "uuid", "p_product_version_id" "uuid", "p_source_type" "text", "p_source_id" "uuid", "p_starts_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_actor_type" "text", "p_actor_id" "uuid", "p_reason" "text", "p_restores_grant_id" "uuid", "p_request_id" "uuid") IS 'Creates every entitlement source through one validated, audited transaction.';



CREATE OR REPLACE FUNCTION "public"."list_user_application_entitlements"("p_user_id" "uuid", "p_application_id" "uuid") RETURNS TABLE("feature" "text", "value" "jsonb", "source_product" "text", "expires_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
  select feature.code, snapshot.value, product.sku, grant_item.expires_at
    from platform.entitlement_grants as grant_item
    join platform.product_version_features as snapshot
      on snapshot.product_version_id = grant_item.product_version_id
    join platform.features as feature
      on feature.id = snapshot.feature_id
     and (feature.app_id is null or feature.app_id = p_application_id)
    join platform.products as product
      on product.id = grant_item.product_id
   where p_user_id is not null
     and p_application_id is not null
     and exists (
       select 1
         from platform.application_memberships as membership
        where membership.application_id = p_application_id
          and membership.user_id = p_user_id
          and membership.status = 'active'
     )
     and grant_item.user_id = p_user_id
     and grant_item.status = 'active'
     and grant_item.starts_at <= timezone('utc', now())
     and (grant_item.expires_at is null or grant_item.expires_at > timezone('utc', now()))
   order by feature.code, grant_item.created_at desc, grant_item.id desc;
$$;


ALTER FUNCTION "public"."list_user_application_entitlements"("p_user_id" "uuid", "p_application_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."list_user_application_entitlements"("p_user_id" "uuid", "p_application_id" "uuid") IS 'Returns only active entitlement features applicable to the verified Application and member.';



CREATE OR REPLACE FUNCTION "public"."list_user_application_memberships"("p_user_id" "uuid") RETURNS TABLE("id" "uuid", "application_id" "uuid", "application_slug" "text", "application_name" "text", "application_category" "text", "application_status" "text", "registration_policy" "text", "membership_policy" "text", "default_locale" "text", "membership_status" "text", "created_source" "text", "joined_at" timestamp with time zone, "activated_at" timestamp with time zone, "suspended_at" timestamp with time zone, "left_at" timestamp with time zone, "deleted_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
  select membership.id,
         app.id,
         app.slug,
         app.name,
         app.category,
         app.status,
         app.registration_policy,
         app.membership_policy,
         app.default_locale,
         membership.status,
         membership.created_source,
         membership.joined_at,
         membership.activated_at,
         membership.suspended_at,
         membership.left_at,
         membership.deleted_at
    from platform.application_memberships as membership
    join platform.platform_apps as app on app.id = membership.application_id
   where p_user_id is not null
     and membership.user_id = p_user_id
     and membership.status <> 'deleted'
   order by membership.joined_at desc, membership.id desc;
$$;


ALTER FUNCTION "public"."list_user_application_memberships"("p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."list_user_application_memberships"("p_user_id" "uuid") IS 'Returns safe application memberships for one Global Identity; private membership records are never directly exposed.';



CREATE OR REPLACE FUNCTION "public"."publish_product_version"("p_product_version_id" "uuid") RETURNS TABLE("product_version_id" "uuid", "status" "text", "published_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  version_row platform.product_versions%rowtype;
  previous_command text := current_setting('app.catalog_command', true);
begin
  select version.*
    into version_row
    from platform.product_versions as version
   where version.id = p_product_version_id
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Product version was not found';
  end if;

  if version_row.status <> 'draft' then
    raise exception using
      errcode = '23514',
      message = 'Only draft product versions can be published';
  end if;

  if not exists (
    select 1
    from platform.product_version_features as feature_snapshot
    where feature_snapshot.product_version_id = version_row.id
  ) then
    raise exception using
      errcode = '23514',
      message = 'A product version needs at least one feature before publication';
  end if;

  if not exists (
    select 1
    from platform.product_prices as price
    where price.product_version_id = version_row.id
      and price.status in ('draft', 'active')
  ) then
    raise exception using
      errcode = '23514',
      message = 'A product version needs at least one price before publication';
  end if;

  perform set_config('app.catalog_command', 'publish', true);
  update platform.product_versions
  set status = 'published',
      published_at = timezone('utc', now())
  where id = version_row.id;
  perform set_config('app.catalog_command', coalesce(previous_command, ''), true);

  return query
  select version.id, version.status, version.published_at
  from platform.product_versions as version
  where version.id = version_row.id;
end;
$$;


ALTER FUNCTION "public"."publish_product_version"("p_product_version_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."publish_product_version"("p_product_version_id" "uuid") IS 'Publishes a complete draft product version through one controlled transaction.';



CREATE OR REPLACE FUNCTION "public"."receive_payment_webhook_event"("p_payment_id" "uuid", "p_order_id" "uuid", "p_provider" "text", "p_external_event_id" "text", "p_event_type" "text", "p_currency" "text", "p_amount" bigint, "p_payload_summary" "jsonb", "p_occurred_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."receive_payment_webhook_event"("p_payment_id" "uuid", "p_order_id" "uuid", "p_provider" "text", "p_external_event_id" "text", "p_event_type" "text", "p_currency" "text", "p_amount" bigint, "p_payload_summary" "jsonb", "p_occurred_at" timestamp with time zone) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."receive_payment_webhook_event"("p_payment_id" "uuid", "p_order_id" "uuid", "p_provider" "text", "p_external_event_id" "text", "p_event_type" "text", "p_currency" "text", "p_amount" bigint, "p_payload_summary" "jsonb", "p_occurred_at" timestamp with time zone) IS 'Atomically records a provider-neutral payment webhook event, deduplicates external identities, and dispatches safe fulfillment or exception handling.';



CREATE OR REPLACE FUNCTION "public"."record_paid_after_cancelled_order"("p_payment_event_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."record_paid_after_cancelled_order"("p_payment_event_id" "uuid", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."record_paid_after_cancelled_order"("p_payment_event_id" "uuid", "p_reason" "text") IS 'Records a paid event received after cancellation as an ignored, audited exception without fulfillment.';



CREATE OR REPLACE FUNCTION "public"."redeem_application_code"("p_code_hash" "text", "p_user_id" "uuid", "p_application_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_ip_hash" "text" DEFAULT NULL::"text") RETURNS TABLE("redemption_id" "uuid", "code_id" "uuid", "batch_id" "uuid", "grant_id" "uuid", "status" "text", "idempotency_record_id" "uuid", "redeemed_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  code_row platform.redemption_codes%rowtype;
  batch_row platform.redemption_batches%rowtype;
  redemption_result record;
begin
  if p_user_id is null or p_application_id is null
     or not exists (
       select 1 from platform.application_memberships as membership
        where membership.application_id = p_application_id
          and membership.user_id = p_user_id
          and membership.status = 'active'
     ) then
    raise exception using errcode = '42501', message = 'An active Application membership is required';
  end if;
  select code.* into code_row
    from platform.redemption_codes as code
   where code.code_hash = p_code_hash;
  if not found then
    raise exception using errcode = 'P0001', message = 'The redemption code is unavailable';
  end if;
  select batch.* into batch_row
    from platform.redemption_batches as batch
   where batch.id = code_row.batch_id;
  if not found or not platform.application_owns_product_version(p_application_id, batch_row.product_version_id) then
    raise exception using errcode = 'P0001', message = 'The redemption code is unavailable';
  end if;

  perform set_config('app.application_id', p_application_id::text, true);
  select * into redemption_result
    from public.redeem_code(p_code_hash, p_user_id, p_idempotency_key, p_request_hash, p_ip_hash);
  return query select redemption_result.redemption_id, redemption_result.code_id,
                      redemption_result.batch_id, redemption_result.grant_id,
                      redemption_result.status, redemption_result.idempotency_record_id,
                      redemption_result.redeemed_at;
end;
$$;


ALTER FUNCTION "public"."redeem_application_code"("p_code_hash" "text", "p_user_id" "uuid", "p_application_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_ip_hash" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."redeem_application_code"("p_code_hash" "text", "p_user_id" "uuid", "p_application_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_ip_hash" "text") IS 'Validates server-resolved Application ownership, then delegates to the atomic redemption state machine.';



CREATE OR REPLACE FUNCTION "public"."redeem_code"("p_code_hash" "text", "p_user_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_ip_hash" "text" DEFAULT NULL::"text") RETURNS TABLE("redemption_id" "uuid", "code_id" "uuid", "batch_id" "uuid", "grant_id" "uuid", "status" "text", "idempotency_record_id" "uuid", "redeemed_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $_$
declare
  idempotency_row platform.idempotency_records%rowtype;
  code_row platform.redemption_codes%rowtype;
  batch_row platform.redemption_batches%rowtype;
  version_row platform.product_versions%rowtype;
  existing_redemption platform.redemptions%rowtype;
  grant_result record;
  redemption_id_value uuid := gen_random_uuid();
  audit_id_value uuid := gen_random_uuid();
  now_value timestamptz := timezone('utc', now());
  response_body_value jsonb;
begin
  if p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = '23514',
      message = 'A normalized redemption code hash is required';
  end if;

  if p_user_id is null or p_idempotency_key is null or btrim(p_idempotency_key) = ''
     or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using
      errcode = '23514',
      message = 'Redemption identity and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('redemption', 'user:' || p_user_id::text, p_idempotency_key, p_request_hash, now_value + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if not found then
    select record.*
      into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'redemption'
       and record.actor_key = 'user:' || p_user_id::text
       and record.idempotency_key = p_idempotency_key
     for update;

    if idempotency_row.request_hash <> p_request_hash then
      raise exception using
        errcode = '23505',
        message = 'The idempotency key was already used for another request';
    end if;

    if idempotency_row.status = 'completed' then
      return query
      select (idempotency_row.response_body ->> 'redemptionId')::uuid,
             (idempotency_row.response_body ->> 'codeId')::uuid,
             (idempotency_row.response_body ->> 'batchId')::uuid,
             (idempotency_row.response_body ->> 'grantId')::uuid,
             idempotency_row.response_body ->> 'status',
             idempotency_row.id,
             (idempotency_row.response_body ->> 'redeemedAt')::timestamptz;
      return;
    end if;
  end if;

  select code.*
    into code_row
    from platform.redemption_codes as code
   where code.code_hash = p_code_hash
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'The redemption code is unavailable';
  end if;

  if code_row.status <> 'issued' then
    select redemption.*
      into existing_redemption
      from platform.redemptions as redemption
     where redemption.code_id = code_row.id;

    if code_row.status = 'redeemed'
       and found
       and existing_redemption.user_id = p_user_id then
      response_body_value := jsonb_build_object(
        'redemptionId', existing_redemption.id,
        'codeId', existing_redemption.code_id,
        'batchId', existing_redemption.batch_id,
        'grantId', existing_redemption.grant_id,
        'status', 'redeemed',
        'redeemedAt', existing_redemption.redeemed_at
      );
      update platform.idempotency_records
      set status = 'completed',
          resource_type = 'redemption',
          resource_id = existing_redemption.id,
          response_status = 200,
          response_body = response_body_value
      where id = idempotency_row.id;

      return query
      select existing_redemption.id, existing_redemption.code_id, existing_redemption.batch_id,
             existing_redemption.grant_id, 'redeemed', idempotency_row.id,
             existing_redemption.redeemed_at;
      return;
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'The redemption code is unavailable';
  end if;

  select batch.*
    into batch_row
    from platform.redemption_batches as batch
   where batch.id = code_row.batch_id
   for update;

  if not found
     or batch_row.status <> 'active'
     or batch_row.starts_at > now_value
     or (batch_row.expires_at is not null and batch_row.expires_at <= now_value) then
    raise exception using
      errcode = 'P0001',
      message = 'The redemption code is unavailable';
  end if;

  select version.*
    into version_row
    from platform.product_versions as version
   where version.id = batch_row.product_version_id
     and version.product_id = batch_row.product_id
   for update;

  if not found or version_row.status <> 'published' then
    raise exception using
      errcode = 'P0001',
      message = 'The redemption code is unavailable';
  end if;

  if (select count(*)
      from platform.redemptions as redemption
     where redemption.batch_id = batch_row.id
       and redemption.user_id = p_user_id)
     >= batch_row.per_user_limit then
    raise exception using
      errcode = 'P0001',
      message = 'The redemption code is unavailable';
  end if;

  select * into grant_result
  from public.grant_entitlement(
    p_user_id,
    version_row.id,
    'redemption',
    redemption_id_value,
    now_value,
    batch_row.expires_at,
    'system',
    null,
    'Redemption code redeemed',
    null,
    null
  );

  insert into platform.redemptions
    (id, code_id, batch_id, user_id, grant_id, idempotency_record_id, ip_hash, redeemed_at)
  values
    (redemption_id_value, code_row.id, batch_row.id, p_user_id, grant_result.grant_id,
     idempotency_row.id, p_ip_hash, now_value);

  update platform.redemption_codes
  set status = 'redeemed', redeemed_at = now_value
  where id = code_row.id;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'user', p_user_id, 'redemptions.redeem', 'redemption', redemption_id_value,
     null, 'Redemption code redeemed', '{}'::jsonb,
     jsonb_build_object('redemptionId', redemption_id_value, 'codeId', code_row.id, 'batchId', batch_row.id));

  response_body_value := jsonb_build_object(
    'redemptionId', redemption_id_value,
    'codeId', code_row.id,
    'batchId', batch_row.id,
    'grantId', grant_result.grant_id,
    'status', 'redeemed',
    'redeemedAt', now_value
  );
  update platform.idempotency_records
  set status = 'completed',
      resource_type = 'redemption',
      resource_id = redemption_id_value,
      response_status = 200,
      response_body = response_body_value
  where id = idempotency_row.id;

  return query
  select redemption_id_value, code_row.id, batch_row.id, grant_result.grant_id,
         'redeemed', idempotency_row.id, now_value;
end;
$_$;


ALTER FUNCTION "public"."redeem_code"("p_code_hash" "text", "p_user_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_ip_hash" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."redeem_code"("p_code_hash" "text", "p_user_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_ip_hash" "text") IS 'Atomically claims one hashed redemption code, creates its entitlement, records the receipt, and saves an idempotent result.';



CREATE OR REPLACE FUNCTION "public"."refund_order_item"("p_order_item_id" "uuid", "p_amount" bigint, "p_mode" "text", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
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


ALTER FUNCTION "public"."refund_order_item"("p_order_item_id" "uuid", "p_amount" bigint, "p_mode" "text", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."refund_order_item"("p_order_item_id" "uuid", "p_amount" bigint, "p_mode" "text", "p_reason" "text") IS 'Atomically refunds one OrderItem, retaining or revoking its sourced entitlement according to explicit mode.';



CREATE OR REPLACE FUNCTION "public"."request_account_deletion"("p_user_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("deletion_request_id" "uuid", "status" "text", "execute_after" timestamp with time zone, "requested_at" timestamp with time zone, "completed_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  idempotency_row platform.idempotency_records%rowtype;
  request_row platform.account_deletion_requests%rowtype;
  profile_status_value text;
  now_value timestamptz := timezone('utc', now());
  audit_id_value uuid := gen_random_uuid();
  response_body_value jsonb;
begin
  if p_user_id is null or p_idempotency_key is null or btrim(p_idempotency_key) = ''
     or length(p_idempotency_key) > 255 or p_request_hash is null or btrim(p_request_hash) = '' then
    raise exception using errcode = '22023', message = 'A user, idempotency key, and request hash are required';
  end if;

  insert into platform.idempotency_records
    (scope, actor_key, idempotency_key, request_hash, expires_at)
  values
    ('account.deletion.request', 'user:' || p_user_id::text, p_idempotency_key, p_request_hash,
     now_value + interval '1 day')
  on conflict (scope, actor_key, idempotency_key) do nothing
  returning * into idempotency_row;

  if idempotency_row.id is null then
    select record.* into idempotency_row
      from platform.idempotency_records as record
     where record.scope = 'account.deletion.request'
       and record.actor_key = 'user:' || p_user_id::text
       and record.idempotency_key = p_idempotency_key
     for update;
    if idempotency_row.request_hash <> p_request_hash then
      raise exception using errcode = 'P0001', message = 'The idempotency key was already used for another request';
    end if;
    if idempotency_row.status = 'completed' then
      return query select
        (idempotency_row.response_body ->> 'deletionRequestId')::uuid,
        idempotency_row.response_body ->> 'status',
        (idempotency_row.response_body ->> 'executeAfter')::timestamptz,
        (idempotency_row.response_body ->> 'requestedAt')::timestamptz,
        nullif(idempotency_row.response_body ->> 'completedAt', '')::timestamptz;
      return;
    end if;
  end if;

  select profile.status into profile_status_value
    from platform.profiles as profile
   where profile.id = p_user_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The account profile was not found';
  end if;
  if profile_status_value <> 'active' then
    raise exception using errcode = '23514', message = 'Only active accounts can request deletion';
  end if;

  insert into platform.account_deletion_requests (user_id, status, execute_after, requested_at)
  values (p_user_id, 'pending', now_value, now_value)
  returning * into request_row;

  update platform.profiles set status = 'deletion_pending' where id = p_user_id;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, 'user', p_user_id, 'account.deletion.requested', 'account_deletion_request',
     request_row.id, p_request_id, 'User requested account deletion',
     jsonb_build_object('profileStatus', 'active'),
     jsonb_build_object('profileStatus', 'deletion_pending', 'status', request_row.status));

  response_body_value := jsonb_build_object(
    'deletionRequestId', request_row.id, 'status', request_row.status,
    'executeAfter', request_row.execute_after, 'requestedAt', request_row.requested_at,
    'completedAt', request_row.completed_at);
  update platform.idempotency_records
     set status = 'completed', resource_type = 'account_deletion_request',
         resource_id = request_row.id, response_status = 202, response_body = response_body_value
   where id = idempotency_row.id;

  return query select request_row.id, request_row.status, request_row.execute_after,
                      request_row.requested_at, request_row.completed_at;
end;
$$;


ALTER FUNCTION "public"."request_account_deletion"("p_user_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."request_account_deletion"("p_user_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") IS 'Creates one pending deletion request, freezes the profile, and records an idempotent audit event.';



CREATE OR REPLACE FUNCTION "public"."resolve_admin_membership"("p_user_id" "uuid") RETURNS TABLE("user_id" "uuid", "display_name" "text", "role" "text", "status" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
  select member.user_id, profile.display_name, member.role, member.status
    from platform.admin_members as member
    join platform.profiles as profile on profile.id = member.user_id
   where member.user_id = p_user_id
     and member.status = 'active'
   limit 1;
$$;


ALTER FUNCTION "public"."resolve_admin_membership"("p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."resolve_admin_membership"("p_user_id" "uuid") IS 'Resolves the active Admin role for a verified bearer identity.';



CREATE OR REPLACE FUNCTION "public"."resolve_app_origin"("p_origin" "text") RETURNS TABLE("app_slug" "text", "environment" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $_$
  select apps.slug, origins.environment
    from platform.app_origins as origins
    join platform.platform_apps as apps on apps.id = origins.app_id
   where origins.origin = $1
     and origins.is_active
     and apps.status = 'active';
$_$;


ALTER FUNCTION "public"."resolve_app_origin"("p_origin" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."resolve_app_origin"("p_origin" "text") IS 'Resolves one exact active Origin to its active application slug; wildcards and declarations are never accepted as authority.';



CREATE OR REPLACE FUNCTION "public"."resolve_application_context"("p_user_id" "uuid", "p_client_id" "text") RETURNS TABLE("user_id" "uuid", "profile_status" "text", "client_id" "text", "client_status" "text", "application_id" "uuid", "application_slug" "text", "application_status" "text", "membership_id" "uuid", "membership_status" "text", "membership_policy" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
  select profile.id,
         profile.status,
         client.external_client_id,
         client.status,
         app.id,
         app.slug,
         app.status,
         membership.id,
         membership.status,
         app.membership_policy
    from platform.profiles as profile
    join platform.application_oauth_clients as client
      on client.external_client_id = p_client_id
    join platform.platform_apps as app
      on app.id = client.application_id
    left join platform.application_memberships as membership
      on membership.application_id = app.id
     and membership.user_id = profile.id
   where p_user_id is not null
     and p_client_id is not null
     and btrim(p_client_id) <> ''
     and profile.id = p_user_id;
$$;


ALTER FUNCTION "public"."resolve_application_context"("p_user_id" "uuid", "p_client_id" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."resolve_application_context"("p_user_id" "uuid", "p_client_id" "text") IS 'Resolves verified user and OAuth client claims into private Application Context facts; it never trusts a request application header.';



CREATE OR REPLACE FUNCTION "public"."restore_entitlement"("p_grant_id" "uuid", "p_actor_id" "uuid", "p_reason" "text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("grant_id" "uuid", "source_id" "uuid", "status" "text", "starts_at" timestamp with time zone, "expires_at" timestamp with time zone, "audit_log_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  original_grant platform.entitlement_grants%rowtype;
begin
  select grant_item.*
    into original_grant
    from platform.entitlement_grants as grant_item
   where grant_item.id = p_grant_id
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Entitlement grant was not found';
  end if;

  if original_grant.status <> 'revoked' then
    raise exception using
      errcode = '23514',
      message = 'Only revoked entitlement grants can be restored';
  end if;

  return query
  select restored.*
  from public.grant_entitlement(
    original_grant.user_id,
    original_grant.product_version_id,
    'admin_restore',
    null,
    timezone('utc', now()),
    original_grant.expires_at,
    'admin',
    p_actor_id,
    p_reason,
    original_grant.id,
    p_request_id
  ) as restored;
end;
$$;


ALTER FUNCTION "public"."restore_entitlement"("p_grant_id" "uuid", "p_actor_id" "uuid", "p_reason" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."restore_entitlement"("p_grant_id" "uuid", "p_actor_id" "uuid", "p_reason" "text", "p_request_id" "uuid") IS 'Creates one new admin_restore entitlement while preserving the revoked original.';



CREATE OR REPLACE FUNCTION "public"."retire_product_version"("p_product_version_id" "uuid") RETURNS TABLE("product_version_id" "uuid", "status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  version_row platform.product_versions%rowtype;
  previous_command text := current_setting('app.catalog_command', true);
begin
  select version.*
    into version_row
    from platform.product_versions as version
   where version.id = p_product_version_id
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Product version was not found';
  end if;

  if version_row.status <> 'published' then
    raise exception using
      errcode = '23514',
      message = 'Only published product versions can be retired';
  end if;

  if exists (
    select 1
    from platform.products as product
    where product.id = version_row.product_id
      and product.current_version_id = version_row.id
  ) then
    raise exception using
      errcode = '23514',
      message = 'The current product version must be changed before retirement';
  end if;

  perform set_config('app.catalog_command', 'retire', true);
  update platform.product_versions
  set status = 'retired'
  where id = version_row.id;

  update platform.product_prices as price
  set status = 'retired'
  where price.product_version_id = version_row.id
    and price.status = 'active';
  perform set_config('app.catalog_command', coalesce(previous_command, ''), true);

  return query
  select version.id, version.status
  from platform.product_versions as version
  where version.id = version_row.id;
end;
$$;


ALTER FUNCTION "public"."retire_product_version"("p_product_version_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."retire_product_version"("p_product_version_id" "uuid") IS 'Retires a non-current published product version and its active prices atomically.';



CREATE OR REPLACE FUNCTION "public"."revoke_entitlement"("p_grant_id" "uuid", "p_actor_type" "text", "p_actor_id" "uuid", "p_reason" "text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("grant_id" "uuid", "status" "text", "revoked_at" timestamp with time zone, "audit_log_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  grant_row platform.entitlement_grants%rowtype;
  revoked_at_value timestamptz := timezone('utc', now());
  audit_id_value uuid := gen_random_uuid();
begin
  if p_reason is null or btrim(p_reason) = '' then
    raise exception using
      errcode = '23514',
      message = 'An entitlement revoke reason is required';
  end if;

  select grant_item.*
    into grant_row
    from platform.entitlement_grants as grant_item
   where grant_item.id = p_grant_id
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Entitlement grant was not found';
  end if;

  if grant_row.status <> 'active' then
    raise exception using
      errcode = '23514',
      message = 'Only active entitlement grants can be revoked';
  end if;

  update platform.entitlement_grants
  set status = 'revoked',
      revoked_at = revoked_at_value,
      revoke_reason = p_reason
  where id = grant_row.id;

  insert into platform.audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, request_id, reason, before_summary, after_summary)
  values
    (audit_id_value, p_actor_type, p_actor_id, 'entitlements.revoke', 'entitlement_grant', grant_row.id,
     p_request_id, p_reason,
     jsonb_build_object('grantId', grant_row.id, 'status', 'active'),
     jsonb_build_object('grantId', grant_row.id, 'status', 'revoked', 'revokedAt', revoked_at_value));

  return query
  select grant_row.id, 'revoked', revoked_at_value, audit_id_value;
end;
$$;


ALTER FUNCTION "public"."revoke_entitlement"("p_grant_id" "uuid", "p_actor_type" "text", "p_actor_id" "uuid", "p_reason" "text", "p_request_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."revoke_entitlement"("p_grant_id" "uuid", "p_actor_type" "text", "p_actor_id" "uuid", "p_reason" "text", "p_request_id" "uuid") IS 'Revokes one active entitlement and writes an audit event atomically.';



CREATE OR REPLACE FUNCTION "public"."run_retention_cleanup"("p_security_context_before" timestamp with time zone, "p_idempotency_response_before" timestamp with time zone, "p_batch_size" integer DEFAULT 100, "p_dry_run" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  redemption_ip_hash_count integer := 0;
  audit_ip_hash_count integer := 0;
  idempotency_response_count integer := 0;
  idempotency_deleted_count integer := 0;
  idempotency_row platform.idempotency_records%rowtype;
begin
  if p_security_context_before is null or p_idempotency_response_before is null then
    raise exception using errcode = '22023', message = 'Cleanup cutoffs are required';
  end if;
  if p_batch_size is null or p_batch_size < 1 or p_batch_size > 1000 then
    raise exception using errcode = '22023', message = 'Cleanup batch size is invalid';
  end if;

  select count(*)::integer
    into redemption_ip_hash_count
    from (
      select redemption.id
        from platform.redemptions as redemption
       where redemption.ip_hash is not null
         and redemption.redeemed_at <= p_security_context_before
       order by redemption.redeemed_at, redemption.id
       limit p_batch_size
    ) as candidates;

  select count(*)::integer
    into audit_ip_hash_count
    from (
      select audit.id
        from platform.audit_logs as audit
       where audit.ip_hash is not null
         and audit.created_at <= p_security_context_before
       order by audit.created_at, audit.id
       limit p_batch_size
    ) as candidates;

  select count(*)::integer
    into idempotency_response_count
    from (
      select record.id
        from platform.idempotency_records as record
       where record.status = 'completed'
         and record.response_body is not null
         and record.expires_at <= p_idempotency_response_before
       order by record.expires_at, record.id
       limit p_batch_size
    ) as candidates;

  if p_dry_run then
    return jsonb_build_object(
      'dryRun', true,
      'redemptionIpHashCount', redemption_ip_hash_count,
      'auditIpHashCount', audit_ip_hash_count,
      'idempotencyResponseCount', idempotency_response_count,
      'idempotencyDeletedCount', 0,
      'batchSize', p_batch_size
    );
  end if;

  set local app.retention_cleanup = 'retention_cleanup';

  with candidates as (
    select redemption.id
      from platform.redemptions as redemption
     where redemption.ip_hash is not null
       and redemption.redeemed_at <= p_security_context_before
     order by redemption.redeemed_at, redemption.id
     limit p_batch_size
     for update skip locked
  )
  update platform.redemptions as redemption
     set ip_hash = null
    from candidates
   where redemption.id = candidates.id;
  get diagnostics redemption_ip_hash_count = row_count;

  set local app.audit_scrub = 'retention_cleanup';

  with candidates as (
    select audit.id
      from platform.audit_logs as audit
     where audit.ip_hash is not null
       and audit.created_at <= p_security_context_before
     order by audit.created_at, audit.id
     limit p_batch_size
     for update skip locked
  )
  update platform.audit_logs as audit
     set ip_hash = null
    from candidates
   where audit.id = candidates.id;
  get diagnostics audit_ip_hash_count = row_count;

  for idempotency_row in
    select record.*
      from platform.idempotency_records as record
     where record.status = 'completed'
       and record.response_body is not null
       and record.expires_at <= p_idempotency_response_before
     order by record.expires_at, record.id
     limit p_batch_size
     for update skip locked
  loop
    if exists (
      select 1 from platform.redemptions as redemption
       where redemption.idempotency_record_id = idempotency_row.id
    ) then
      update platform.idempotency_records
         set response_body = null,
             response_status = null
       where id = idempotency_row.id;
    else
      delete from platform.idempotency_records
       where id = idempotency_row.id;
      idempotency_deleted_count := idempotency_deleted_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'dryRun', false,
    'redemptionIpHashCount', redemption_ip_hash_count,
    'auditIpHashCount', audit_ip_hash_count,
    'idempotencyResponseCount', idempotency_response_count,
    'idempotencyDeletedCount', idempotency_deleted_count,
    'batchSize', p_batch_size
  );
end;
$$;


ALTER FUNCTION "public"."run_retention_cleanup"("p_security_context_before" timestamp with time zone, "p_idempotency_response_before" timestamp with time zone, "p_batch_size" integer, "p_dry_run" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."run_retention_cleanup"("p_security_context_before" timestamp with time zone, "p_idempotency_response_before" timestamp with time zone, "p_batch_size" integer, "p_dry_run" boolean) IS 'Runs one bounded, retry-safe cleanup batch for short-lived IP hashes and expired idempotency response bodies.';



CREATE OR REPLACE FUNCTION "public"."set_current_product_version"("p_product_id" "uuid", "p_product_version_id" "uuid") RETURNS TABLE("product_id" "uuid", "current_version_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'platform'
    AS $$
declare
  selected_version platform.product_versions%rowtype;
  product_row platform.products%rowtype;
  previous_command text := current_setting('app.catalog_command', true);
begin
  select product.*
    into product_row
    from platform.products as product
   where product.id = p_product_id
   for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Product was not found';
  end if;

  if product_row.status = 'archived' then
    raise exception using
      errcode = '23514',
      message = 'Archived products cannot select a current version';
  end if;

  select version.*
    into selected_version
    from platform.product_versions as version
   where version.id = p_product_version_id
     and version.product_id = p_product_id
   for update;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'Current product version must belong to the product';
  end if;

  if selected_version.status <> 'published' then
    raise exception using
      errcode = '23514',
      message = 'Current product version must be published';
  end if;

  if not exists (
    select 1
    from platform.product_prices as price
    where price.product_version_id = selected_version.id
      and price.status = 'active'
      and price.valid_from <= timezone('utc', now())
      and (price.valid_until is null or price.valid_until > timezone('utc', now()))
  ) then
    raise exception using
      errcode = '23514',
      message = 'Current product version must have an active price';
  end if;

  perform set_config('app.catalog_command', 'set_current', true);
  update platform.products
  set current_version_id = selected_version.id
  where id = product_row.id;
  perform set_config('app.catalog_command', coalesce(previous_command, ''), true);

  return query
  select product.id, product.current_version_id
  from platform.products as product
  where product.id = product_row.id;
end;
$$;


ALTER FUNCTION "public"."set_current_product_version"("p_product_id" "uuid", "p_product_version_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."set_current_product_version"("p_product_id" "uuid", "p_product_version_id" "uuid") IS 'Sets a product current version only after ownership, publication, and active-price checks.';


SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "platform"."account_deletion_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "execute_after" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "attempt_count" integer DEFAULT 0 NOT NULL,
    "last_error_code" "text",
    "next_attempt_at" timestamp with time zone,
    "worker_id" "uuid",
    "processing_started_at" timestamp with time zone,
    "requested_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "completed_at" timestamp with time zone,
    "cancelled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "account_deletion_requests_attempt_count_check" CHECK (("attempt_count" >= 0)),
    CONSTRAINT "account_deletion_requests_cancelled_at_check" CHECK ((("status" = 'cancelled'::"text") = ("cancelled_at" IS NOT NULL))),
    CONSTRAINT "account_deletion_requests_completed_at_check" CHECK ((("status" = 'completed'::"text") = ("completed_at" IS NOT NULL))),
    CONSTRAINT "account_deletion_requests_error_code_check" CHECK ((("last_error_code" IS NULL) OR ("last_error_code" ~ '^[A-Z][A-Z0-9_]{1,63}$'::"text"))),
    CONSTRAINT "account_deletion_requests_failed_retry_check" CHECK ((("status" <> 'failed'::"text") OR ("next_attempt_at" IS NOT NULL))),
    CONSTRAINT "account_deletion_requests_processing_fields_check" CHECK (((("status" = 'processing'::"text") AND ("worker_id" IS NOT NULL) AND ("processing_started_at" IS NOT NULL)) OR (("status" <> 'processing'::"text") AND ("worker_id" IS NULL) AND ("processing_started_at" IS NULL)))),
    CONSTRAINT "account_deletion_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'processing'::"text", 'completed'::"text", 'failed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "platform"."account_deletion_requests" OWNER TO "postgres";


COMMENT ON TABLE "platform"."account_deletion_requests" IS 'Recoverable account deletion workflow state; Auth anonymization is an external retryable step.';



COMMENT ON COLUMN "platform"."account_deletion_requests"."last_error_code" IS 'Stable operational code only; sensitive external error text is never stored.';



CREATE TABLE IF NOT EXISTS "platform"."admin_members" (
    "user_id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_by" "uuid",
    "disabled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "admin_members_disabled_at_check" CHECK ((("status" = 'disabled'::"text") = ("disabled_at" IS NOT NULL))),
    CONSTRAINT "admin_members_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'admin'::"text", 'support'::"text", 'finance'::"text"]))),
    CONSTRAINT "admin_members_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'disabled'::"text"])))
);


ALTER TABLE "platform"."admin_members" OWNER TO "postgres";


COMMENT ON TABLE "platform"."admin_members" IS 'Backend-owned fixed four-role Admin membership; it is not a profile or JWT role.';



CREATE TABLE IF NOT EXISTS "platform"."app_origins" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "app_id" "uuid" NOT NULL,
    "environment" "text" NOT NULL,
    "origin" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "app_origins_environment_check" CHECK (("environment" = ANY (ARRAY['development'::"text", 'staging'::"text", 'production'::"text"]))),
    CONSTRAINT "app_origins_origin_exact_check" CHECK ((("origin" = "lower"("origin")) AND ("origin" !~ '[*[:space:]]'::"text") AND ("origin" ~ '^https?://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?$'::"text")))
);


ALTER TABLE "platform"."app_origins" OWNER TO "postgres";


COMMENT ON TABLE "platform"."app_origins" IS 'Exact Origin allow-list used by the backend to derive the calling application.';



COMMENT ON COLUMN "platform"."app_origins"."origin" IS 'Canonical scheme, host, and optional port only; paths, wildcards, query strings, and fragments are rejected.';



CREATE TABLE IF NOT EXISTS "platform"."application_memberships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "application_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_source" "text" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "activated_at" timestamp with time zone,
    "suspended_at" timestamp with time zone,
    "suspended_reason" "text",
    "left_at" timestamp with time zone,
    "deleted_at" timestamp with time zone,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "application_memberships_activated_at_check" CHECK ((("activated_at" IS NULL) OR ("activated_at" >= "joined_at"))),
    CONSTRAINT "application_memberships_active_shape_check" CHECK ((("status" <> 'active'::"text") OR ("activated_at" IS NOT NULL))),
    CONSTRAINT "application_memberships_deleted_at_check" CHECK ((("deleted_at" IS NULL) OR ("deleted_at" >= "joined_at"))),
    CONSTRAINT "application_memberships_deleted_shape_check" CHECK ((("status" = 'deleted'::"text") = ("deleted_at" IS NOT NULL))),
    CONSTRAINT "application_memberships_joined_at_check" CHECK (("joined_at" >= "created_at")),
    CONSTRAINT "application_memberships_left_at_check" CHECK ((("left_at" IS NULL) OR ("left_at" >= "joined_at"))),
    CONSTRAINT "application_memberships_left_shape_check" CHECK ((("status" <> ALL (ARRAY['left'::"text", 'deleted'::"text"])) OR ("left_at" IS NOT NULL))),
    CONSTRAINT "application_memberships_source_nonempty_check" CHECK ((("btrim"("created_source") <> ''::"text") AND ("length"("created_source") <= 100))),
    CONSTRAINT "application_memberships_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'active'::"text", 'suspended'::"text", 'left'::"text", 'deleted'::"text"]))),
    CONSTRAINT "application_memberships_suspended_at_check" CHECK ((("suspended_at" IS NULL) OR ("suspended_at" >= "joined_at"))),
    CONSTRAINT "application_memberships_suspended_shape_check" CHECK ((("status" = 'suspended'::"text") = (("suspended_at" IS NOT NULL) AND ("suspended_reason" IS NOT NULL) AND ("btrim"("suspended_reason") <> ''::"text"))))
);


ALTER TABLE "platform"."application_memberships" OWNER TO "postgres";


COMMENT ON TABLE "platform"."application_memberships" IS 'Application-scoped user membership; Global Identity existence never grants membership implicitly.';



COMMENT ON COLUMN "platform"."application_memberships"."created_source" IS 'Controlled backend reason such as admin, oauth, purchase, self_service or system.';



CREATE TABLE IF NOT EXISTS "platform"."application_oauth_clients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "application_id" "uuid" NOT NULL,
    "provider" "text" NOT NULL,
    "external_client_id" "text" NOT NULL,
    "client_type" "text" NOT NULL,
    "environment" "text" NOT NULL,
    "name" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "application_oauth_clients_client_type_check" CHECK (("client_type" = ANY (ARRAY['public'::"text", 'confidential'::"text"]))),
    CONSTRAINT "application_oauth_clients_environment_check" CHECK (("environment" = ANY (ARRAY['development'::"text", 'staging'::"text", 'production'::"text"]))),
    CONSTRAINT "application_oauth_clients_external_id_nonempty_check" CHECK ((("btrim"("external_client_id") <> ''::"text") AND ("length"("external_client_id") <= 255))),
    CONSTRAINT "application_oauth_clients_name_nonempty_check" CHECK ((("btrim"("name") <> ''::"text") AND ("length"("name") <= 200))),
    CONSTRAINT "application_oauth_clients_provider_nonempty_check" CHECK ((("btrim"("provider") <> ''::"text") AND ("length"("provider") <= 100))),
    CONSTRAINT "application_oauth_clients_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'disabled'::"text"])))
);


ALTER TABLE "platform"."application_oauth_clients" OWNER TO "postgres";


COMMENT ON TABLE "platform"."application_oauth_clients" IS 'Private binding from a verified provider client_id to exactly one Application.';



COMMENT ON COLUMN "platform"."application_oauth_clients"."external_client_id" IS 'Provider client_id only; client secrets and redirect configuration remain with the provider.';



CREATE TABLE IF NOT EXISTS "platform"."audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "actor_type" "text" NOT NULL,
    "actor_id" "uuid",
    "action" "text" NOT NULL,
    "target_type" "text" NOT NULL,
    "target_id" "uuid" NOT NULL,
    "request_id" "uuid",
    "reason" "text" NOT NULL,
    "before_summary" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "after_summary" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "ip_hash" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "application_id" "uuid",
    CONSTRAINT "audit_logs_action_nonempty_check" CHECK (("btrim"("action") <> ''::"text")),
    CONSTRAINT "audit_logs_actor_type_check" CHECK (("actor_type" = ANY (ARRAY['admin'::"text", 'system'::"text", 'user'::"text", 'webhook'::"text"]))),
    CONSTRAINT "audit_logs_after_summary_object_check" CHECK (("jsonb_typeof"("after_summary") = 'object'::"text")),
    CONSTRAINT "audit_logs_before_summary_object_check" CHECK (("jsonb_typeof"("before_summary") = 'object'::"text")),
    CONSTRAINT "audit_logs_reason_nonempty_check" CHECK (("btrim"("reason") <> ''::"text")),
    CONSTRAINT "audit_logs_target_type_nonempty_check" CHECK (("btrim"("target_type") <> ''::"text"))
);


ALTER TABLE "platform"."audit_logs" OWNER TO "postgres";


COMMENT ON TABLE "platform"."audit_logs" IS 'Append-only authoritative audit history for backend business commands.';



CREATE TABLE IF NOT EXISTS "platform"."entitlement_grants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "product_version_id" "uuid" NOT NULL,
    "resolution_mode" "text" DEFAULT 'snapshot'::"text" NOT NULL,
    "source_type" "text" NOT NULL,
    "source_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "starts_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "expires_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "revoke_reason" "text",
    "restores_grant_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "application_id" "uuid",
    CONSTRAINT "entitlement_grants_expiry_check" CHECK ((("expires_at" IS NULL) OR ("expires_at" > "starts_at"))),
    CONSTRAINT "entitlement_grants_resolution_mode_check" CHECK (("resolution_mode" = 'snapshot'::"text")),
    CONSTRAINT "entitlement_grants_restore_not_self_check" CHECK ((("restores_grant_id" IS NULL) OR ("restores_grant_id" <> "id"))),
    CONSTRAINT "entitlement_grants_restore_shape_check" CHECK ((("source_type" = 'admin_restore'::"text") = ("restores_grant_id" IS NOT NULL))),
    CONSTRAINT "entitlement_grants_revocation_fields_check" CHECK (((("status" = 'active'::"text") AND ("revoked_at" IS NULL) AND ("revoke_reason" IS NULL)) OR (("status" = 'revoked'::"text") AND ("revoked_at" IS NOT NULL) AND ("revoke_reason" IS NOT NULL) AND ("btrim"("revoke_reason") <> ''::"text")))),
    CONSTRAINT "entitlement_grants_source_type_check" CHECK (("source_type" = ANY (ARRAY['order_item'::"text", 'redemption'::"text", 'admin'::"text", 'promotion'::"text", 'admin_restore'::"text"]))),
    CONSTRAINT "entitlement_grants_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'revoked'::"text"])))
);


ALTER TABLE "platform"."entitlement_grants" OWNER TO "postgres";


COMMENT ON TABLE "platform"."entitlement_grants" IS 'Append-only business entitlement history; access is resolved from all valid grants, not a user role.';



COMMENT ON COLUMN "platform"."entitlement_grants"."product_version_id" IS 'The product version promised at grant time; it never follows the product current version.';



CREATE TABLE IF NOT EXISTS "platform"."entitlement_restore_links" (
    "restores_grant_id" "uuid" NOT NULL,
    "restored_grant_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "platform"."entitlement_restore_links" OWNER TO "postgres";


COMMENT ON TABLE "platform"."entitlement_restore_links" IS 'One-time restore policy: one original grant can produce at most one restore grant.';



CREATE TABLE IF NOT EXISTS "platform"."features" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "app_id" "uuid",
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "value_type" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "merge_strategy" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "features_code_format_check" CHECK ((("code" = "lower"("code")) AND ("code" ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'::"text"))),
    CONSTRAINT "features_merge_strategy_check" CHECK (("merge_strategy" = ANY (ARRAY['any_true'::"text", 'sum'::"text", 'max'::"text", 'min'::"text", 'latest'::"text"]))),
    CONSTRAINT "features_merge_strategy_type_check" CHECK (((("value_type" = 'boolean'::"text") AND ("merge_strategy" = 'any_true'::"text")) OR (("value_type" = 'integer'::"text") AND ("merge_strategy" = ANY (ARRAY['sum'::"text", 'max'::"text", 'min'::"text", 'latest'::"text"]))) OR (("value_type" = ANY (ARRAY['string'::"text", 'json'::"text"])) AND ("merge_strategy" = 'latest'::"text")))),
    CONSTRAINT "features_name_nonempty_check" CHECK (("btrim"("name") <> ''::"text")),
    CONSTRAINT "features_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'retired'::"text"]))),
    CONSTRAINT "features_value_type_check" CHECK (("value_type" = ANY (ARRAY['boolean'::"text", 'integer'::"text", 'string'::"text", 'json'::"text"])))
);


ALTER TABLE "platform"."features" OWNER TO "postgres";


COMMENT ON TABLE "platform"."features" IS 'Backend-owned atomic entitlement features; feature definitions are not user roles.';



CREATE TABLE IF NOT EXISTS "platform"."feedback_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "app_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "kind" "text" NOT NULL,
    "title" "text" NOT NULL,
    "content" "text" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "membership_id" "uuid",
    CONSTRAINT "feedback_requests_content_nonempty_check" CHECK (("btrim"("content") <> ''::"text")),
    CONSTRAINT "feedback_requests_kind_nonempty_check" CHECK (("btrim"("kind") <> ''::"text")),
    CONSTRAINT "feedback_requests_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'in_progress'::"text", 'resolved'::"text", 'closed'::"text"]))),
    CONSTRAINT "feedback_requests_title_nonempty_check" CHECK (("btrim"("title") <> ''::"text"))
);


ALTER TABLE "platform"."feedback_requests" OWNER TO "postgres";


COMMENT ON TABLE "platform"."feedback_requests" IS 'User feedback attributed to the server-resolved application, never to a client-supplied app ID.';



COMMENT ON COLUMN "platform"."feedback_requests"."user_id" IS 'Nullable direct user link; cleared when account deletion de-identifies feedback.';



CREATE TABLE IF NOT EXISTS "platform"."idempotency_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "scope" "text" NOT NULL,
    "actor_key" "text" NOT NULL,
    "idempotency_key" "text" NOT NULL,
    "request_hash" "text" NOT NULL,
    "status" "text" DEFAULT 'in_progress'::"text" NOT NULL,
    "resource_type" "text",
    "resource_id" "uuid",
    "response_status" integer,
    "response_body" "jsonb",
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "idempotency_records_actor_key_nonempty" CHECK (("btrim"("actor_key") <> ''::"text")),
    CONSTRAINT "idempotency_records_hash_nonempty" CHECK (("btrim"("request_hash") <> ''::"text")),
    CONSTRAINT "idempotency_records_key_nonempty" CHECK (("btrim"("idempotency_key") <> ''::"text")),
    CONSTRAINT "idempotency_records_resource_pair_check" CHECK ((("resource_type" IS NULL) = ("resource_id" IS NULL))),
    CONSTRAINT "idempotency_records_response_status_check" CHECK ((("response_status" IS NULL) OR (("response_status" >= 100) AND ("response_status" <= 599)))),
    CONSTRAINT "idempotency_records_scope_nonempty" CHECK (("btrim"("scope") <> ''::"text")),
    CONSTRAINT "idempotency_records_status_check" CHECK (("status" = ANY (ARRAY['in_progress'::"text", 'completed'::"text", 'failed'::"text"])))
);


ALTER TABLE "platform"."idempotency_records" OWNER TO "postgres";


COMMENT ON TABLE "platform"."idempotency_records" IS 'Backend-owned command retry records; the request hash prevents key reuse for a different request.';



COMMENT ON COLUMN "platform"."idempotency_records"."actor_key" IS 'Stable identity key for a user, administrator, webhook, or service actor.';



COMMENT ON COLUMN "platform"."idempotency_records"."request_hash" IS 'Hash of the canonical request payload used to reject same-key/different-request reuse.';



CREATE TABLE IF NOT EXISTS "platform"."order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "product_version_id" "uuid" NOT NULL,
    "product_price_id" "uuid",
    "quantity" integer DEFAULT 1 NOT NULL,
    "unit_amount" bigint NOT NULL,
    "total_amount" bigint NOT NULL,
    "product_name" "text" NOT NULL,
    "sku_snapshot" "text" NOT NULL,
    "sales_terms" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "fulfillment_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "refunded_amount" bigint DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "order_items_fulfillment_status_check" CHECK (("fulfillment_status" = ANY (ARRAY['pending'::"text", 'granted'::"text", 'revoked'::"text"]))),
    CONSTRAINT "order_items_product_name_nonempty_check" CHECK (("btrim"("product_name") <> ''::"text")),
    CONSTRAINT "order_items_quantity_check" CHECK (("quantity" = 1)),
    CONSTRAINT "order_items_refunded_amount_check" CHECK ((("refunded_amount" >= 0) AND ("refunded_amount" <= "total_amount"))),
    CONSTRAINT "order_items_sales_terms_object_check" CHECK (("jsonb_typeof"("sales_terms") = 'object'::"text")),
    CONSTRAINT "order_items_sku_snapshot_format_check" CHECK ((("sku_snapshot" = "upper"("sku_snapshot")) AND ("sku_snapshot" ~ '^[A-Z0-9][A-Z0-9_-]*$'::"text"))),
    CONSTRAINT "order_items_total_amount_check" CHECK ((("total_amount" >= 0) AND ("total_amount" = ("unit_amount" * "quantity")))),
    CONSTRAINT "order_items_unit_amount_check" CHECK (("unit_amount" >= 0))
);


ALTER TABLE "platform"."order_items" OWNER TO "postgres";


COMMENT ON TABLE "platform"."order_items" IS 'Smallest fulfillment and refund unit with a frozen purchase snapshot.';



COMMENT ON COLUMN "platform"."order_items"."sales_terms" IS 'Terms captured at purchase time; it is not re-read from a mutable catalog row.';



CREATE TABLE IF NOT EXISTS "platform"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_no" "text" NOT NULL,
    "user_id" "uuid",
    "customer_ref" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "currency" character(3) NOT NULL,
    "amount_total" bigint NOT NULL,
    "channel" "text" NOT NULL,
    "paid_at" timestamp with time zone,
    "fulfilled_at" timestamp with time zone,
    "cancelled_at" timestamp with time zone,
    "refunded_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "application_id" "uuid",
    CONSTRAINT "orders_amount_total_check" CHECK (("amount_total" >= 0)),
    CONSTRAINT "orders_cancelled_at_consistency_check" CHECK ((("status" = 'cancelled'::"text") = ("cancelled_at" IS NOT NULL))),
    CONSTRAINT "orders_channel_check" CHECK ((("channel" = ANY (ARRAY['manual'::"text", 'code_sale'::"text"])) OR ("channel" ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'::"text"))),
    CONSTRAINT "orders_currency_check" CHECK (("currency" ~ '^[A-Z]{3}$'::"text")),
    CONSTRAINT "orders_customer_ref_not_null" CHECK (("customer_ref" IS NOT NULL)),
    CONSTRAINT "orders_fulfilled_at_consistency_check" CHECK (((("status" = ANY (ARRAY['fulfilled'::"text", 'partially_refunded'::"text", 'refunded'::"text", 'chargeback'::"text"])) AND ("fulfilled_at" IS NOT NULL)) OR ("status" <> ALL (ARRAY['fulfilled'::"text", 'partially_refunded'::"text", 'refunded'::"text", 'chargeback'::"text"])))),
    CONSTRAINT "orders_order_no_nonempty_check" CHECK (("btrim"("order_no") <> ''::"text")),
    CONSTRAINT "orders_paid_at_consistency_check" CHECK (((("status" = 'pending'::"text") AND ("paid_at" IS NULL)) OR (("status" = 'cancelled'::"text") AND ("paid_at" IS NULL)) OR (("status" = ANY (ARRAY['paid'::"text", 'fulfilled'::"text", 'partially_refunded'::"text", 'refunded'::"text", 'chargeback'::"text"])) AND ("paid_at" IS NOT NULL)))),
    CONSTRAINT "orders_refunded_at_consistency_check" CHECK ((("status" = 'refunded'::"text") = ("refunded_at" IS NOT NULL))),
    CONSTRAINT "orders_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'paid'::"text", 'fulfilled'::"text", 'cancelled'::"text", 'partially_refunded'::"text", 'refunded'::"text", 'chargeback'::"text"]))),
    CONSTRAINT "orders_timestamp_order_check" CHECK (((("paid_at" IS NULL) OR ("paid_at" >= "created_at")) AND (("fulfilled_at" IS NULL) OR ("fulfilled_at" >= COALESCE("paid_at", "created_at"))) AND (("cancelled_at" IS NULL) OR ("cancelled_at" >= "created_at")) AND (("refunded_at" IS NULL) OR ("refunded_at" >= COALESCE("fulfilled_at", "paid_at", "created_at")))))
);


ALTER TABLE "platform"."orders" OWNER TO "postgres";


COMMENT ON TABLE "platform"."orders" IS 'Backend-owned order facts; user_id may be anonymized while customer_ref preserves historical linkage.';



COMMENT ON COLUMN "platform"."orders"."customer_ref" IS 'Non-personal historical customer reference retained when the direct user link is cleared.';



CREATE TABLE IF NOT EXISTS "platform"."payment_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "payment_id" "uuid" NOT NULL,
    "order_id" "uuid" NOT NULL,
    "provider" "text" NOT NULL,
    "external_event_id" "text" NOT NULL,
    "event_type" "text" NOT NULL,
    "status" "text" DEFAULT 'received'::"text" NOT NULL,
    "currency" character(3) NOT NULL,
    "amount" bigint NOT NULL,
    "payload_summary" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "occurred_at" timestamp with time zone NOT NULL,
    "processed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "payment_events_amount_check" CHECK (("amount" >= 0)),
    CONSTRAINT "payment_events_currency_check" CHECK (("currency" ~ '^[A-Z]{3}$'::"text")),
    CONSTRAINT "payment_events_external_id_check" CHECK ((("btrim"("external_event_id") <> ''::"text") AND ("external_event_id" !~ '[[:space:]]'::"text"))),
    CONSTRAINT "payment_events_processed_at_check" CHECK (((("status" = 'received'::"text") AND ("processed_at" IS NULL)) OR (("status" = ANY (ARRAY['processed'::"text", 'ignored'::"text", 'failed'::"text"])) AND ("processed_at" IS NOT NULL)))),
    CONSTRAINT "payment_events_provider_check" CHECK (("provider" ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'::"text")),
    CONSTRAINT "payment_events_status_check" CHECK (("status" = ANY (ARRAY['received'::"text", 'processed'::"text", 'ignored'::"text", 'failed'::"text"]))),
    CONSTRAINT "payment_events_summary_object_check" CHECK (("jsonb_typeof"("payload_summary") = 'object'::"text")),
    CONSTRAINT "payment_events_summary_size_check" CHECK (("octet_length"(("payload_summary")::"text") <= 32768)),
    CONSTRAINT "payment_events_timestamp_order_check" CHECK ((("occurred_at" <= "created_at") AND (("processed_at" IS NULL) OR ("processed_at" >= "created_at")))),
    CONSTRAINT "payment_events_type_check" CHECK (("event_type" ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'::"text"))
);


ALTER TABLE "platform"."payment_events" OWNER TO "postgres";


COMMENT ON TABLE "platform"."payment_events" IS 'Backend-owned minimized payment event facts used for webhook idempotency; raw credentials are not stored.';



COMMENT ON COLUMN "platform"."payment_events"."payload_summary" IS 'Small validated summary only; never store raw webhook bodies, tokens, card data, or credentials.';



CREATE TABLE IF NOT EXISTS "platform"."payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "provider" "text" NOT NULL,
    "external_payment_id" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "currency" character(3) NOT NULL,
    "amount" bigint NOT NULL,
    "failure_code" "text",
    "paid_at" timestamp with time zone,
    "refunded_at" timestamp with time zone,
    "disputed_at" timestamp with time zone,
    "failed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "payments_amount_check" CHECK (("amount" >= 0)),
    CONSTRAINT "payments_currency_check" CHECK (("currency" ~ '^[A-Z]{3}$'::"text")),
    CONSTRAINT "payments_external_id_check" CHECK ((("external_payment_id" IS NULL) OR (("btrim"("external_payment_id") <> ''::"text") AND ("external_payment_id" !~ '[[:space:]]'::"text")))),
    CONSTRAINT "payments_failure_code_check" CHECK ((("failure_code" IS NULL) OR ("failure_code" ~ '^[A-Z0-9][A-Z0-9_.-]*$'::"text"))),
    CONSTRAINT "payments_provider_check" CHECK (("provider" ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'::"text")),
    CONSTRAINT "payments_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'succeeded'::"text", 'partially_refunded'::"text", 'refunded'::"text", 'disputed'::"text", 'failed'::"text"]))),
    CONSTRAINT "payments_status_timestamps_check" CHECK (((("status" = 'pending'::"text") AND ("paid_at" IS NULL) AND ("refunded_at" IS NULL) AND ("disputed_at" IS NULL) AND ("failed_at" IS NULL)) OR (("status" = 'succeeded'::"text") AND ("paid_at" IS NOT NULL) AND ("refunded_at" IS NULL) AND ("disputed_at" IS NULL) AND ("failed_at" IS NULL)) OR (("status" = 'partially_refunded'::"text") AND ("paid_at" IS NOT NULL) AND ("refunded_at" IS NOT NULL) AND ("disputed_at" IS NULL) AND ("failed_at" IS NULL)) OR (("status" = 'refunded'::"text") AND ("paid_at" IS NOT NULL) AND ("refunded_at" IS NOT NULL) AND ("disputed_at" IS NULL) AND ("failed_at" IS NULL)) OR (("status" = 'disputed'::"text") AND ("paid_at" IS NOT NULL) AND ("disputed_at" IS NOT NULL) AND ("refunded_at" IS NULL) AND ("failed_at" IS NULL)) OR (("status" = 'failed'::"text") AND ("paid_at" IS NULL) AND ("refunded_at" IS NULL) AND ("disputed_at" IS NULL) AND ("failed_at" IS NOT NULL)))),
    CONSTRAINT "payments_timestamp_order_check" CHECK (((("paid_at" IS NULL) OR ("paid_at" >= "created_at")) AND (("refunded_at" IS NULL) OR ("refunded_at" >= COALESCE("paid_at", "created_at"))) AND (("disputed_at" IS NULL) OR ("disputed_at" >= COALESCE("paid_at", "created_at"))) AND (("failed_at" IS NULL) OR ("failed_at" >= "created_at"))))
);


ALTER TABLE "platform"."payments" OWNER TO "postgres";


COMMENT ON TABLE "platform"."payments" IS 'Backend-owned payment identity and status; no complete payment credentials are stored.';



COMMENT ON COLUMN "platform"."payments"."external_payment_id" IS 'Provider transaction identity only; secrets and complete payment credentials are prohibited.';



CREATE TABLE IF NOT EXISTS "platform"."platform_apps" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "primary_feature_id" "uuid",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "registration_policy" "text" DEFAULT 'open'::"text" NOT NULL,
    "membership_policy" "text" DEFAULT 'explicit'::"text" NOT NULL,
    "default_locale" "text",
    "terms_version" "text",
    "privacy_version" "text",
    CONSTRAINT "platform_apps_category_nonempty_check" CHECK (("btrim"("category") <> ''::"text")),
    CONSTRAINT "platform_apps_default_locale_format_check" CHECK ((("default_locale" IS NULL) OR ("default_locale" ~ '^[A-Za-z]{2}(-[A-Za-z0-9]{2,8})?$'::"text"))),
    CONSTRAINT "platform_apps_membership_policy_check" CHECK (("membership_policy" = ANY (ARRAY['explicit'::"text", 'create_on_first_authorization'::"text", 'create_on_verified_purchase'::"text"]))),
    CONSTRAINT "platform_apps_metadata_object_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "platform_apps_name_nonempty_check" CHECK (("btrim"("name") <> ''::"text")),
    CONSTRAINT "platform_apps_privacy_version_nonempty_check" CHECK ((("privacy_version" IS NULL) OR ("btrim"("privacy_version") <> ''::"text"))),
    CONSTRAINT "platform_apps_registration_policy_check" CHECK (("registration_policy" = ANY (ARRAY['open'::"text", 'invite_only'::"text", 'admin_created'::"text", 'closed'::"text"]))),
    CONSTRAINT "platform_apps_slug_format_check" CHECK (("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::"text")),
    CONSTRAINT "platform_apps_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'active'::"text", 'suspended'::"text", 'retired'::"text"]))),
    CONSTRAINT "platform_apps_terms_version_nonempty_check" CHECK ((("terms_version" IS NULL) OR ("btrim"("terms_version") <> ''::"text")))
);


ALTER TABLE "platform"."platform_apps" OWNER TO "postgres";


COMMENT ON TABLE "platform"."platform_apps" IS 'Backend-owned registry of applications that may use the Platform API.';



COMMENT ON COLUMN "platform"."platform_apps"."slug" IS 'Lowercase machine identity; it becomes immutable once an Origin references the app.';



COMMENT ON COLUMN "platform"."platform_apps"."primary_feature_id" IS 'Reserved for the Catalog feature registry introduced in a later migration.';



COMMENT ON COLUMN "platform"."platform_apps"."registration_policy" IS 'Controls who may register for this application; it is not an authentication role.';



COMMENT ON COLUMN "platform"."platform_apps"."membership_policy" IS 'Controls how an authenticated identity becomes an application member.';



CREATE TABLE IF NOT EXISTS "platform"."product_prices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_version_id" "uuid" NOT NULL,
    "currency" character(3) NOT NULL,
    "amount_minor" bigint NOT NULL,
    "channel" "text" NOT NULL,
    "external_price_id" "text",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "valid_from" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "valid_until" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "product_prices_amount_check" CHECK (("amount_minor" >= 0)),
    CONSTRAINT "product_prices_channel_check" CHECK ((("channel" = ANY (ARRAY['manual'::"text", 'redemption'::"text"])) OR ("channel" ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'::"text"))),
    CONSTRAINT "product_prices_currency_check" CHECK (("currency" ~ '^[A-Z]{3}$'::"text")),
    CONSTRAINT "product_prices_external_id_check" CHECK ((("external_price_id" IS NULL) OR ("btrim"("external_price_id") <> ''::"text"))),
    CONSTRAINT "product_prices_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'active'::"text", 'retired'::"text"]))),
    CONSTRAINT "product_prices_valid_window_check" CHECK ((("valid_until" IS NULL) OR ("valid_until" > "valid_from")))
);


ALTER TABLE "platform"."product_prices" OWNER TO "postgres";


COMMENT ON TABLE "platform"."product_prices" IS 'Channel and currency pricing independent from immutable product-version sales terms.';



CREATE TABLE IF NOT EXISTS "platform"."product_version_features" (
    "product_version_id" "uuid" NOT NULL,
    "feature_id" "uuid" NOT NULL,
    "value" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "platform"."product_version_features" OWNER TO "postgres";


COMMENT ON TABLE "platform"."product_version_features" IS 'Feature values promised by a specific product version; published snapshots are immutable.';



CREATE TABLE IF NOT EXISTS "platform"."product_versions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "version" integer NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "access_duration_days" integer,
    "sales_terms" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "published_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "product_versions_access_duration_check" CHECK ((("access_duration_days" IS NULL) OR ("access_duration_days" > 0))),
    CONSTRAINT "product_versions_published_at_check" CHECK (((("status" = 'draft'::"text") AND ("published_at" IS NULL)) OR (("status" = ANY (ARRAY['published'::"text", 'retired'::"text"])) AND ("published_at" IS NOT NULL)))),
    CONSTRAINT "product_versions_sales_terms_object_check" CHECK (("jsonb_typeof"("sales_terms") = 'object'::"text")),
    CONSTRAINT "product_versions_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'published'::"text", 'retired'::"text"]))),
    CONSTRAINT "product_versions_version_positive_check" CHECK (("version" > 0))
);


ALTER TABLE "platform"."product_versions" OWNER TO "postgres";


COMMENT ON TABLE "platform"."product_versions" IS 'Frozen sales commitments; published and retired versions cannot be edited or deleted.';



CREATE TABLE IF NOT EXISTS "platform"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sku" "text" NOT NULL,
    "name" "text" NOT NULL,
    "billing_type" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "current_version_id" "uuid",
    "entitlement_policy" "text" DEFAULT 'snapshot'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "products_billing_type_check" CHECK (("billing_type" = ANY (ARRAY['one_time'::"text", 'subscription'::"text", 'credits'::"text"]))),
    CONSTRAINT "products_entitlement_policy_check" CHECK (("entitlement_policy" = ANY (ARRAY['snapshot'::"text", 'all_apps_access'::"text"]))),
    CONSTRAINT "products_name_nonempty_check" CHECK (("btrim"("name") <> ''::"text")),
    CONSTRAINT "products_sku_format_check" CHECK ((("sku" = "upper"("sku")) AND ("sku" ~ '^[A-Z0-9][A-Z0-9_-]*$'::"text"))),
    CONSTRAINT "products_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'active'::"text", 'archived'::"text"])))
);


ALTER TABLE "platform"."products" OWNER TO "postgres";


COMMENT ON TABLE "platform"."products" IS 'Stable sales identities; prices and entitlement snapshots are versioned separately.';



CREATE TABLE IF NOT EXISTS "platform"."profiles" (
    "id" "uuid" NOT NULL,
    "display_name" "text",
    "avatar_url" "text",
    "locale" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "profiles_deleted_at_consistency_check" CHECK ((("status" = 'deleted'::"text") = ("deleted_at" IS NOT NULL))),
    CONSTRAINT "profiles_display_name_nonempty_check" CHECK ((("display_name" IS NULL) OR ("btrim"("display_name") <> ''::"text"))),
    CONSTRAINT "profiles_locale_format_check" CHECK ((("locale" IS NULL) OR ("locale" ~ '^[A-Za-z]{2}(-[A-Za-z0-9]{2,8})?$'::"text"))),
    CONSTRAINT "profiles_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'disabled'::"text", 'deletion_pending'::"text", 'deleted'::"text"])))
);


ALTER TABLE "platform"."profiles" OWNER TO "postgres";


COMMENT ON TABLE "platform"."profiles" IS 'Platform-owned user profile metadata; authentication credentials remain in Supabase Auth.';



COMMENT ON COLUMN "platform"."profiles"."id" IS 'Immutable one-to-one reference to auth.users.id.';



COMMENT ON COLUMN "platform"."profiles"."status" IS 'Account lifecycle only; it is not a product role or entitlement.';



CREATE TABLE IF NOT EXISTS "platform"."redemption_batches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "product_version_id" "uuid" NOT NULL,
    "resolution_mode" "text" DEFAULT 'snapshot'::"text" NOT NULL,
    "code_prefix" "text" NOT NULL,
    "quantity" integer NOT NULL,
    "per_user_limit" integer DEFAULT 1 NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "starts_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "expires_at" timestamp with time zone,
    "source" "text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "redemption_batches_code_prefix_check" CHECK ((("code_prefix" = "upper"("code_prefix")) AND ("code_prefix" ~ '^[A-Z0-9]+(?:-[A-Z0-9]+)*$'::"text"))),
    CONSTRAINT "redemption_batches_expiry_check" CHECK ((("expires_at" IS NULL) OR ("expires_at" > "starts_at"))),
    CONSTRAINT "redemption_batches_name_nonempty_check" CHECK (("btrim"("name") <> ''::"text")),
    CONSTRAINT "redemption_batches_per_user_limit_check" CHECK ((("per_user_limit" > 0) AND ("per_user_limit" <= "quantity"))),
    CONSTRAINT "redemption_batches_quantity_check" CHECK (("quantity" > 0)),
    CONSTRAINT "redemption_batches_resolution_mode_check" CHECK (("resolution_mode" = 'snapshot'::"text")),
    CONSTRAINT "redemption_batches_source_nonempty_check" CHECK (("btrim"("source") <> ''::"text")),
    CONSTRAINT "redemption_batches_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'active'::"text", 'paused'::"text", 'closed'::"text"])))
);


ALTER TABLE "platform"."redemption_batches" OWNER TO "postgres";


COMMENT ON TABLE "platform"."redemption_batches" IS 'Backend-owned redemption campaigns tied to one immutable product-version snapshot.';



CREATE TABLE IF NOT EXISTS "platform"."redemption_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "batch_id" "uuid" NOT NULL,
    "code_hash" "text" NOT NULL,
    "code_hint" "text" NOT NULL,
    "pepper_version" smallint NOT NULL,
    "status" "text" DEFAULT 'issued'::"text" NOT NULL,
    "redeemed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "redemption_codes_hash_format_check" CHECK (("code_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "redemption_codes_hint_nonempty_check" CHECK (("btrim"("code_hint") <> ''::"text")),
    CONSTRAINT "redemption_codes_pepper_version_check" CHECK (("pepper_version" > 0)),
    CONSTRAINT "redemption_codes_redeemed_at_check" CHECK (((("status" = 'issued'::"text") AND ("redeemed_at" IS NULL)) OR (("status" = 'redeemed'::"text") AND ("redeemed_at" IS NOT NULL)) OR (("status" = 'revoked'::"text") AND ("redeemed_at" IS NULL)))),
    CONSTRAINT "redemption_codes_status_check" CHECK (("status" = ANY (ARRAY['issued'::"text", 'redeemed'::"text", 'revoked'::"text"])))
);


ALTER TABLE "platform"."redemption_codes" OWNER TO "postgres";


COMMENT ON TABLE "platform"."redemption_codes" IS 'One-time redemption credentials; only HMAC digests and non-sensitive hints are stored.';



CREATE TABLE IF NOT EXISTS "platform"."redemptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code_id" "uuid" NOT NULL,
    "batch_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "grant_id" "uuid" NOT NULL,
    "idempotency_record_id" "uuid" NOT NULL,
    "ip_hash" "text",
    "redeemed_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "application_id" "uuid",
    CONSTRAINT "redemptions_ip_hash_nonempty_check" CHECK ((("ip_hash" IS NULL) OR ("btrim"("ip_hash") <> ''::"text")))
);


ALTER TABLE "platform"."redemptions" OWNER TO "postgres";


COMMENT ON TABLE "platform"."redemptions" IS 'Immutable redemption receipts linking one code, user, entitlement grant, and idempotency record.';



ALTER TABLE ONLY "platform"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."admin_members"
    ADD CONSTRAINT "admin_members_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "platform"."app_origins"
    ADD CONSTRAINT "app_origins_origin_key" UNIQUE ("origin");



ALTER TABLE ONLY "platform"."app_origins"
    ADD CONSTRAINT "app_origins_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."application_memberships"
    ADD CONSTRAINT "application_memberships_application_user_key" UNIQUE ("application_id", "user_id");



ALTER TABLE ONLY "platform"."application_memberships"
    ADD CONSTRAINT "application_memberships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."application_oauth_clients"
    ADD CONSTRAINT "application_oauth_clients_external_id_key" UNIQUE ("external_client_id");



ALTER TABLE ONLY "platform"."application_oauth_clients"
    ADD CONSTRAINT "application_oauth_clients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."audit_logs"
    ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."entitlement_grants"
    ADD CONSTRAINT "entitlement_grants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."entitlement_grants"
    ADD CONSTRAINT "entitlement_grants_source_key" UNIQUE ("source_type", "source_id");



ALTER TABLE ONLY "platform"."entitlement_restore_links"
    ADD CONSTRAINT "entitlement_restore_links_pkey" PRIMARY KEY ("restores_grant_id");



ALTER TABLE ONLY "platform"."entitlement_restore_links"
    ADD CONSTRAINT "entitlement_restore_links_restored_grant_id_key" UNIQUE ("restored_grant_id");



ALTER TABLE ONLY "platform"."features"
    ADD CONSTRAINT "features_code_key" UNIQUE ("code");



ALTER TABLE ONLY "platform"."features"
    ADD CONSTRAINT "features_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."feedback_requests"
    ADD CONSTRAINT "feedback_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."idempotency_records"
    ADD CONSTRAINT "idempotency_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."idempotency_records"
    ADD CONSTRAINT "idempotency_records_scope_actor_key_unique" UNIQUE ("scope", "actor_key", "idempotency_key");



ALTER TABLE ONLY "platform"."order_items"
    ADD CONSTRAINT "order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."orders"
    ADD CONSTRAINT "orders_order_no_key" UNIQUE ("order_no");



ALTER TABLE ONLY "platform"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."payment_events"
    ADD CONSTRAINT "payment_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."payments"
    ADD CONSTRAINT "payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."platform_apps"
    ADD CONSTRAINT "platform_apps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."platform_apps"
    ADD CONSTRAINT "platform_apps_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "platform"."product_prices"
    ADD CONSTRAINT "product_prices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."product_version_features"
    ADD CONSTRAINT "product_version_features_pkey" PRIMARY KEY ("product_version_id", "feature_id");



ALTER TABLE ONLY "platform"."product_versions"
    ADD CONSTRAINT "product_versions_id_product_key" UNIQUE ("id", "product_id");



ALTER TABLE ONLY "platform"."product_versions"
    ADD CONSTRAINT "product_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."product_versions"
    ADD CONSTRAINT "product_versions_product_version_key" UNIQUE ("product_id", "version");



ALTER TABLE ONLY "platform"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."products"
    ADD CONSTRAINT "products_sku_key" UNIQUE ("sku");



ALTER TABLE ONLY "platform"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."redemption_batches"
    ADD CONSTRAINT "redemption_batches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."redemption_codes"
    ADD CONSTRAINT "redemption_codes_code_hash_key" UNIQUE ("code_hash");



ALTER TABLE ONLY "platform"."redemption_codes"
    ADD CONSTRAINT "redemption_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "platform"."redemptions"
    ADD CONSTRAINT "redemptions_code_id_key" UNIQUE ("code_id");



ALTER TABLE ONLY "platform"."redemptions"
    ADD CONSTRAINT "redemptions_grant_id_key" UNIQUE ("grant_id");



ALTER TABLE ONLY "platform"."redemptions"
    ADD CONSTRAINT "redemptions_idempotency_record_id_key" UNIQUE ("idempotency_record_id");



ALTER TABLE ONLY "platform"."redemptions"
    ADD CONSTRAINT "redemptions_pkey" PRIMARY KEY ("id");



CREATE INDEX "account_deletion_requests_due_idx" ON "platform"."account_deletion_requests" USING "btree" ("execute_after", "next_attempt_at", "requested_at") WHERE ("status" = ANY (ARRAY['pending'::"text", 'failed'::"text"]));



CREATE UNIQUE INDEX "account_deletion_requests_one_open_idx" ON "platform"."account_deletion_requests" USING "btree" ("user_id") WHERE ("status" = ANY (ARRAY['pending'::"text", 'processing'::"text", 'failed'::"text"]));



CREATE INDEX "account_deletion_requests_status_idx" ON "platform"."account_deletion_requests" USING "btree" ("status", "requested_at" DESC);



CREATE INDEX "admin_members_created_by_idx" ON "platform"."admin_members" USING "btree" ("created_by");



CREATE INDEX "admin_members_role_status_idx" ON "platform"."admin_members" USING "btree" ("role", "status");



CREATE INDEX "app_origins_active_lookup_idx" ON "platform"."app_origins" USING "btree" ("origin", "is_active") WHERE "is_active";



CREATE INDEX "app_origins_app_id_idx" ON "platform"."app_origins" USING "btree" ("app_id");



CREATE INDEX "application_memberships_application_status_idx" ON "platform"."application_memberships" USING "btree" ("application_id", "status");



CREATE INDEX "application_memberships_user_status_idx" ON "platform"."application_memberships" USING "btree" ("user_id", "status");



CREATE INDEX "application_oauth_clients_application_status_idx" ON "platform"."application_oauth_clients" USING "btree" ("application_id", "status");



CREATE INDEX "application_oauth_clients_environment_idx" ON "platform"."application_oauth_clients" USING "btree" ("environment", "status");



CREATE INDEX "audit_logs_application_created_idx" ON "platform"."audit_logs" USING "btree" ("application_id", "created_at" DESC) WHERE ("application_id" IS NOT NULL);



CREATE INDEX "audit_logs_ip_hash_created_at_idx" ON "platform"."audit_logs" USING "btree" ("created_at") WHERE ("ip_hash" IS NOT NULL);



CREATE INDEX "audit_logs_request_id_idx" ON "platform"."audit_logs" USING "btree" ("request_id") WHERE ("request_id" IS NOT NULL);



CREATE INDEX "audit_logs_target_created_idx" ON "platform"."audit_logs" USING "btree" ("target_type", "target_id", "created_at" DESC);



CREATE INDEX "entitlement_grants_application_status_idx" ON "platform"."entitlement_grants" USING "btree" ("application_id", "status", "created_at" DESC);



CREATE INDEX "entitlement_grants_product_status_idx" ON "platform"."entitlement_grants" USING "btree" ("product_id", "status");



CREATE INDEX "entitlement_grants_restores_grant_id_idx" ON "platform"."entitlement_grants" USING "btree" ("restores_grant_id") WHERE ("restores_grant_id" IS NOT NULL);



CREATE INDEX "entitlement_grants_user_status_expiry_idx" ON "platform"."entitlement_grants" USING "btree" ("user_id", "status", "expires_at");



CREATE INDEX "feedback_requests_app_created_idx" ON "platform"."feedback_requests" USING "btree" ("app_id", "created_at" DESC);



CREATE INDEX "feedback_requests_membership_created_idx" ON "platform"."feedback_requests" USING "btree" ("membership_id", "created_at" DESC) WHERE ("membership_id" IS NOT NULL);



CREATE INDEX "feedback_requests_user_created_idx" ON "platform"."feedback_requests" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idempotency_records_expires_at_idx" ON "platform"."idempotency_records" USING "btree" ("expires_at");



CREATE INDEX "order_items_fulfillment_status_idx" ON "platform"."order_items" USING "btree" ("fulfillment_status", "created_at");



CREATE INDEX "order_items_order_idx" ON "platform"."order_items" USING "btree" ("order_id", "created_at");



CREATE INDEX "order_items_product_version_idx" ON "platform"."order_items" USING "btree" ("product_id", "product_version_id");



CREATE INDEX "orders_application_status_idx" ON "platform"."orders" USING "btree" ("application_id", "status", "created_at" DESC);



CREATE INDEX "orders_customer_ref_idx" ON "platform"."orders" USING "btree" ("customer_ref");



CREATE INDEX "orders_status_created_idx" ON "platform"."orders" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "orders_user_status_idx" ON "platform"."orders" USING "btree" ("user_id", "status", "created_at" DESC);



CREATE INDEX "payment_events_order_created_idx" ON "platform"."payment_events" USING "btree" ("order_id", "created_at" DESC);



CREATE INDEX "payment_events_payment_created_idx" ON "platform"."payment_events" USING "btree" ("payment_id", "created_at" DESC);



CREATE UNIQUE INDEX "payment_events_provider_external_id_key" ON "platform"."payment_events" USING "btree" ("provider", "external_event_id");



CREATE INDEX "payments_order_status_idx" ON "platform"."payments" USING "btree" ("order_id", "status", "created_at" DESC);



CREATE UNIQUE INDEX "payments_provider_external_id_key" ON "platform"."payments" USING "btree" ("provider", "external_payment_id") WHERE ("external_payment_id" IS NOT NULL);



CREATE INDEX "payments_status_created_idx" ON "platform"."payments" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "platform_apps_status_idx" ON "platform"."platform_apps" USING "btree" ("status");



CREATE UNIQUE INDEX "product_prices_channel_external_id_key" ON "platform"."product_prices" USING "btree" ("channel", "external_price_id") WHERE ("external_price_id" IS NOT NULL);



CREATE INDEX "product_prices_version_status_idx" ON "platform"."product_prices" USING "btree" ("product_version_id", "status");



CREATE INDEX "product_version_features_feature_id_idx" ON "platform"."product_version_features" USING "btree" ("feature_id");



CREATE INDEX "profiles_created_at_idx" ON "platform"."profiles" USING "btree" ("created_at");



CREATE INDEX "profiles_status_idx" ON "platform"."profiles" USING "btree" ("status");



CREATE INDEX "redemption_batches_status_window_idx" ON "platform"."redemption_batches" USING "btree" ("status", "starts_at", "expires_at");



CREATE INDEX "redemption_codes_batch_status_idx" ON "platform"."redemption_codes" USING "btree" ("batch_id", "status");



CREATE INDEX "redemptions_application_redeemed_at_idx" ON "platform"."redemptions" USING "btree" ("application_id", "redeemed_at" DESC);



CREATE INDEX "redemptions_batch_redeemed_at_idx" ON "platform"."redemptions" USING "btree" ("batch_id", "redeemed_at" DESC);



CREATE INDEX "redemptions_ip_hash_redeemed_at_idx" ON "platform"."redemptions" USING "btree" ("redeemed_at") WHERE ("ip_hash" IS NOT NULL);



CREATE INDEX "redemptions_user_redeemed_at_idx" ON "platform"."redemptions" USING "btree" ("user_id", "redeemed_at" DESC);



CREATE OR REPLACE TRIGGER "account_deletion_requests_set_updated_at" BEFORE UPDATE ON "platform"."account_deletion_requests" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "admin_members_prevent_identity_change" BEFORE UPDATE ON "platform"."admin_members" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_admin_member_identity_change"();



CREATE OR REPLACE TRIGGER "admin_members_set_updated_at" BEFORE UPDATE ON "platform"."admin_members" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "app_origins_prevent_identity_change" BEFORE UPDATE ON "platform"."app_origins" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_origin_identity_change"();



CREATE OR REPLACE TRIGGER "app_origins_set_updated_at" BEFORE UPDATE ON "platform"."app_origins" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "application_memberships_prevent_identity_change" BEFORE UPDATE ON "platform"."application_memberships" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_application_membership_identity_change"();



CREATE OR REPLACE TRIGGER "application_memberships_set_updated_at" BEFORE UPDATE ON "platform"."application_memberships" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "application_oauth_clients_prevent_identity_change" BEFORE UPDATE ON "platform"."application_oauth_clients" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_application_oauth_client_identity_change"();



CREATE OR REPLACE TRIGGER "application_oauth_clients_set_updated_at" BEFORE UPDATE ON "platform"."application_oauth_clients" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "audit_logs_assign_application_context" BEFORE INSERT ON "platform"."audit_logs" FOR EACH ROW EXECUTE FUNCTION "platform"."assign_audit_application_context"();



CREATE OR REPLACE TRIGGER "audit_logs_prevent_update" BEFORE DELETE OR UPDATE ON "platform"."audit_logs" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_audit_log_mutation"();



CREATE OR REPLACE TRIGGER "entitlement_grants_application_immutable" BEFORE UPDATE ON "platform"."entitlement_grants" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_entitlement_application_change"();



CREATE OR REPLACE TRIGGER "entitlement_grants_assign_application_context" BEFORE INSERT ON "platform"."entitlement_grants" FOR EACH ROW EXECUTE FUNCTION "platform"."assign_application_context_to_entitlement"();



CREATE OR REPLACE TRIGGER "entitlement_grants_prevent_mutation" BEFORE DELETE OR UPDATE ON "platform"."entitlement_grants" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_entitlement_grant_mutation"();



CREATE OR REPLACE TRIGGER "entitlement_grants_validate_application_scope" BEFORE INSERT OR UPDATE ON "platform"."entitlement_grants" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_application_scoped_entitlement"();



CREATE OR REPLACE TRIGGER "entitlement_grants_validate_restore" BEFORE INSERT OR UPDATE ON "platform"."entitlement_grants" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_entitlement_restore_link"();



CREATE OR REPLACE TRIGGER "feedback_requests_set_updated_at" BEFORE UPDATE ON "platform"."feedback_requests" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "feedback_requests_validate_membership" BEFORE INSERT OR UPDATE ON "platform"."feedback_requests" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_feedback_membership"();



CREATE OR REPLACE TRIGGER "idempotency_records_set_updated_at" BEFORE UPDATE ON "platform"."idempotency_records" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "order_items_set_updated_at" BEFORE UPDATE ON "platform"."order_items" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "order_items_validate_application_scope" BEFORE INSERT OR UPDATE ON "platform"."order_items" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_application_scoped_order_item"();



CREATE OR REPLACE TRIGGER "order_items_validate_snapshot" BEFORE INSERT OR DELETE OR UPDATE ON "platform"."order_items" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_order_item_snapshot"();



CREATE OR REPLACE TRIGGER "order_items_validate_total" AFTER INSERT OR DELETE OR UPDATE ON "platform"."order_items" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_order_total"();



CREATE OR REPLACE TRIGGER "orders_set_updated_at" BEFORE UPDATE ON "platform"."orders" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "orders_validate_total" AFTER INSERT OR UPDATE ON "platform"."orders" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_order_total"();



CREATE OR REPLACE TRIGGER "payment_events_set_updated_at" BEFORE UPDATE ON "platform"."payment_events" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "payment_events_validate_consistency" BEFORE INSERT OR UPDATE ON "platform"."payment_events" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_payment_event_consistency"();



CREATE OR REPLACE TRIGGER "payments_set_updated_at" BEFORE UPDATE ON "platform"."payments" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "payments_validate_consistency" BEFORE INSERT OR UPDATE ON "platform"."payments" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_payment_consistency"();



CREATE OR REPLACE TRIGGER "platform_apps_prevent_referenced_slug_change" BEFORE UPDATE ON "platform"."platform_apps" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_referenced_app_slug_change"();



CREATE OR REPLACE TRIGGER "platform_apps_set_updated_at" BEFORE UPDATE ON "platform"."platform_apps" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "product_prices_set_updated_at" BEFORE UPDATE ON "platform"."product_prices" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "product_prices_validate_status" BEFORE INSERT OR UPDATE ON "platform"."product_prices" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_product_price_status"();



CREATE OR REPLACE TRIGGER "product_version_features_prevent_mutation" BEFORE DELETE OR UPDATE ON "platform"."product_version_features" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_product_version_feature_mutation"();



CREATE OR REPLACE TRIGGER "product_version_features_validate_value" BEFORE INSERT OR UPDATE ON "platform"."product_version_features" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_product_version_feature_value"();



CREATE OR REPLACE TRIGGER "product_versions_prevent_mutation" BEFORE DELETE OR UPDATE ON "platform"."product_versions" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_product_version_mutation"();



CREATE OR REPLACE TRIGGER "product_versions_protect_current" BEFORE UPDATE ON "platform"."product_versions" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_current_retired_version"();



CREATE OR REPLACE TRIGGER "products_set_updated_at" BEFORE UPDATE ON "platform"."products" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "products_validate_current_version" BEFORE INSERT OR UPDATE ON "platform"."products" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_product_current_version"();



CREATE OR REPLACE TRIGGER "profiles_prevent_identity_change" BEFORE UPDATE ON "platform"."profiles" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_profile_identity_change"();



CREATE OR REPLACE TRIGGER "profiles_set_updated_at" BEFORE UPDATE ON "platform"."profiles" FOR EACH ROW EXECUTE FUNCTION "platform"."set_updated_at"();



CREATE OR REPLACE TRIGGER "redemption_codes_prevent_mutation" BEFORE DELETE OR UPDATE ON "platform"."redemption_codes" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_redemption_code_mutation"();



CREATE OR REPLACE TRIGGER "redemptions_application_immutable" BEFORE UPDATE ON "platform"."redemptions" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_redemption_application_change"();



CREATE OR REPLACE TRIGGER "redemptions_assign_application_context" BEFORE INSERT ON "platform"."redemptions" FOR EACH ROW EXECUTE FUNCTION "platform"."assign_application_context_to_redemption"();



CREATE OR REPLACE TRIGGER "redemptions_prevent_mutation" BEFORE DELETE OR UPDATE ON "platform"."redemptions" FOR EACH ROW EXECUTE FUNCTION "platform"."prevent_redemption_mutation"();



CREATE OR REPLACE TRIGGER "redemptions_validate_consistency" BEFORE INSERT OR UPDATE ON "platform"."redemptions" FOR EACH ROW EXECUTE FUNCTION "platform"."validate_redemption_consistency"();



ALTER TABLE ONLY "platform"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."admin_members"
    ADD CONSTRAINT "admin_members_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "platform"."admin_members"
    ADD CONSTRAINT "admin_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."app_origins"
    ADD CONSTRAINT "app_origins_app_id_fkey" FOREIGN KEY ("app_id") REFERENCES "platform"."platform_apps"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."application_memberships"
    ADD CONSTRAINT "application_memberships_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "platform"."platform_apps"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."application_memberships"
    ADD CONSTRAINT "application_memberships_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "platform"."application_memberships"
    ADD CONSTRAINT "application_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."application_oauth_clients"
    ADD CONSTRAINT "application_oauth_clients_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "platform"."platform_apps"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."audit_logs"
    ADD CONSTRAINT "audit_logs_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "platform"."platform_apps"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."entitlement_grants"
    ADD CONSTRAINT "entitlement_grants_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "platform"."platform_apps"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."entitlement_grants"
    ADD CONSTRAINT "entitlement_grants_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "platform"."products"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."entitlement_grants"
    ADD CONSTRAINT "entitlement_grants_product_version_fk" FOREIGN KEY ("product_version_id", "product_id") REFERENCES "platform"."product_versions"("id", "product_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."entitlement_grants"
    ADD CONSTRAINT "entitlement_grants_restores_grant_id_fkey" FOREIGN KEY ("restores_grant_id") REFERENCES "platform"."entitlement_grants"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."entitlement_grants"
    ADD CONSTRAINT "entitlement_grants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."entitlement_restore_links"
    ADD CONSTRAINT "entitlement_restore_links_restored_grant_id_fkey" FOREIGN KEY ("restored_grant_id") REFERENCES "platform"."entitlement_grants"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."entitlement_restore_links"
    ADD CONSTRAINT "entitlement_restore_links_restores_grant_id_fkey" FOREIGN KEY ("restores_grant_id") REFERENCES "platform"."entitlement_grants"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."features"
    ADD CONSTRAINT "features_app_id_fkey" FOREIGN KEY ("app_id") REFERENCES "platform"."platform_apps"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."feedback_requests"
    ADD CONSTRAINT "feedback_requests_app_id_fkey" FOREIGN KEY ("app_id") REFERENCES "platform"."platform_apps"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."feedback_requests"
    ADD CONSTRAINT "feedback_requests_membership_id_fkey" FOREIGN KEY ("membership_id") REFERENCES "platform"."application_memberships"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."feedback_requests"
    ADD CONSTRAINT "feedback_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."order_items"
    ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "platform"."orders"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."order_items"
    ADD CONSTRAINT "order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "platform"."products"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."order_items"
    ADD CONSTRAINT "order_items_product_price_id_fkey" FOREIGN KEY ("product_price_id") REFERENCES "platform"."product_prices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."order_items"
    ADD CONSTRAINT "order_items_product_version_fk" FOREIGN KEY ("product_version_id", "product_id") REFERENCES "platform"."product_versions"("id", "product_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."orders"
    ADD CONSTRAINT "orders_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "platform"."platform_apps"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."orders"
    ADD CONSTRAINT "orders_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "platform"."payment_events"
    ADD CONSTRAINT "payment_events_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "platform"."orders"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."payment_events"
    ADD CONSTRAINT "payment_events_payment_id_fkey" FOREIGN KEY ("payment_id") REFERENCES "platform"."payments"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."payments"
    ADD CONSTRAINT "payments_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "platform"."orders"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."product_prices"
    ADD CONSTRAINT "product_prices_product_version_id_fkey" FOREIGN KEY ("product_version_id") REFERENCES "platform"."product_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."product_version_features"
    ADD CONSTRAINT "product_version_features_feature_id_fkey" FOREIGN KEY ("feature_id") REFERENCES "platform"."features"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."product_version_features"
    ADD CONSTRAINT "product_version_features_product_version_id_fkey" FOREIGN KEY ("product_version_id") REFERENCES "platform"."product_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."product_versions"
    ADD CONSTRAINT "product_versions_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "platform"."products"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."products"
    ADD CONSTRAINT "products_current_version_ownership_fk" FOREIGN KEY ("current_version_id", "id") REFERENCES "platform"."product_versions"("id", "product_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "platform"."redemption_batches"
    ADD CONSTRAINT "redemption_batches_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."redemption_batches"
    ADD CONSTRAINT "redemption_batches_product_version_fk" FOREIGN KEY ("product_version_id", "product_id") REFERENCES "platform"."product_versions"("id", "product_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."redemption_codes"
    ADD CONSTRAINT "redemption_codes_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "platform"."redemption_batches"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."redemptions"
    ADD CONSTRAINT "redemptions_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "platform"."platform_apps"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."redemptions"
    ADD CONSTRAINT "redemptions_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "platform"."redemption_batches"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."redemptions"
    ADD CONSTRAINT "redemptions_code_id_fkey" FOREIGN KEY ("code_id") REFERENCES "platform"."redemption_codes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."redemptions"
    ADD CONSTRAINT "redemptions_grant_id_fkey" FOREIGN KEY ("grant_id") REFERENCES "platform"."entitlement_grants"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."redemptions"
    ADD CONSTRAINT "redemptions_idempotency_record_id_fkey" FOREIGN KEY ("idempotency_record_id") REFERENCES "platform"."idempotency_records"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "platform"."redemptions"
    ADD CONSTRAINT "redemptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE "platform"."account_deletion_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."admin_members" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."app_origins" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."application_memberships" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."application_oauth_clients" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."audit_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."entitlement_grants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."entitlement_restore_links" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."features" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."feedback_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."order_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."payment_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."payments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."platform_apps" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."product_prices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."product_version_features" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."product_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."redemption_batches" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."redemption_codes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "platform"."redemptions" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "platform"."application_owns_product_version"("p_application_id" "uuid", "p_product_version_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."assign_application_context_to_entitlement"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."assign_application_context_to_redemption"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."assign_audit_application_context"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."cleanup_application_data"("p_membership_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."handle_new_auth_user"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."payment_event_summary_is_safe"("value" "jsonb") FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_admin_member_identity_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_application_membership_identity_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_application_oauth_client_identity_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_audit_log_mutation"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_current_retired_version"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_entitlement_application_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_entitlement_grant_mutation"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_origin_identity_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_product_version_feature_mutation"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_product_version_mutation"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_profile_identity_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_redemption_application_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_redemption_code_mutation"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_redemption_mutation"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."prevent_referenced_app_slug_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."set_updated_at"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_application_scoped_entitlement"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_application_scoped_order_item"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_entitlement_restore_link"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_feedback_membership"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_order_item_snapshot"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_order_total"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_payment_consistency"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_payment_event_consistency"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_product_current_version"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_product_price_status"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_product_version_feature_value"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "platform"."validate_redemption_consistency"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."admin_application_membership_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_application_membership_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_catalog_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_catalog_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_catalog_draft_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_parent_id" "uuid", "p_payload" "jsonb", "p_expected_updated_at" timestamp with time zone, "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_catalog_draft_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_parent_id" "uuid", "p_payload" "jsonb", "p_expected_updated_at" timestamp with time zone, "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_catalog_resource_detail"("p_actor_id" "uuid", "p_resource" "text", "p_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_catalog_resource_detail"("p_actor_id" "uuid", "p_resource" "text", "p_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_customer_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_customer_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_application_memberships"("p_actor_id" "uuid", "p_application_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_application_memberships"("p_actor_id" "uuid", "p_application_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_application_oauth_clients"("p_actor_id" "uuid", "p_application_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_application_oauth_clients"("p_actor_id" "uuid", "p_application_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_oauth_client_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_client_id" "uuid", "p_provider" "text", "p_external_client_id" "text", "p_client_type" "text", "p_environment" "text", "p_name" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_oauth_client_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_client_id" "uuid", "p_provider" "text", "p_external_client_id" "text", "p_client_type" "text", "p_environment" "text", "p_name" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_operations_overview"("p_actor_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_operations_overview"("p_actor_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_order_overview"("p_actor_id" "uuid", "p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_order_overview"("p_actor_id" "uuid", "p_order_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_product_overview"("p_actor_id" "uuid", "p_product_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_product_overview"("p_actor_id" "uuid", "p_product_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_query_catalog_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_query_catalog_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_query_commerce_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_query_commerce_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_query_customer_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_query_customer_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_query_products"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_query_products"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_query_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text", "p_application_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_query_resource"("p_actor_id" "uuid", "p_resource" "text", "p_cursor" "text", "p_limit" integer, "p_search" "text", "p_status" "text", "p_sort" "text", "p_direction" "text", "p_application_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_redemption_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_redemption_command"("p_actor_id" "uuid", "p_action" "text", "p_resource_id" "uuid", "p_payload" "jsonb", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_refund_order_item"("p_actor_id" "uuid", "p_order_item_id" "uuid", "p_amount" bigint, "p_mode" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_refund_order_item"("p_actor_id" "uuid", "p_order_item_id" "uuid", "p_amount" bigint, "p_mode" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_user_overview"("p_actor_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_user_overview"("p_actor_id" "uuid", "p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_verify_order"("p_actor_id" "uuid", "p_order_id" "uuid", "p_payment_reference" "text", "p_amount" bigint, "p_currency" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_verify_order"("p_actor_id" "uuid", "p_order_id" "uuid", "p_payment_reference" "text", "p_amount" bigint, "p_currency" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."application_membership_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_created_source" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."application_membership_command"("p_actor_id" "uuid", "p_action" "text", "p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_created_source" "text", "p_reason" "text", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_account_deletion"("p_user_id" "uuid", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_account_deletion"("p_user_id" "uuid", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."chargeback_order"("p_order_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."chargeback_order"("p_order_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."check_access"("p_user_id" "uuid", "p_app_slug" "text", "p_feature_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."check_access"("p_user_id" "uuid", "p_app_slug" "text", "p_feature_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."check_application_access"("p_user_id" "uuid", "p_application_id" "uuid", "p_feature_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."check_application_access"("p_user_id" "uuid", "p_application_id" "uuid", "p_feature_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_account_deletion_request"("p_worker_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_account_deletion_request"("p_worker_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_account_deletion_request"("p_deletion_request_id" "uuid", "p_worker_id" "uuid", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_account_deletion_request"("p_deletion_request_id" "uuid", "p_worker_id" "uuid", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_application_feedback"("p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_kind" "text", "p_title" "text", "p_content" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_application_feedback"("p_application_id" "uuid", "p_user_id" "uuid", "p_membership_id" "uuid", "p_kind" "text", "p_title" "text", "p_content" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_profile"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_profile"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."fail_account_deletion_request"("p_request_id" "uuid", "p_worker_id" "uuid", "p_error_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fail_account_deletion_request"("p_request_id" "uuid", "p_worker_id" "uuid", "p_error_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."fulfill_paid_order"("p_payment_event_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fulfill_paid_order"("p_payment_event_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_public_app"("app_slug" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_public_app"("app_slug" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_public_app"("app_slug" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_public_products"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_public_products"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_public_products"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."grant_entitlement"("p_user_id" "uuid", "p_product_version_id" "uuid", "p_source_type" "text", "p_source_id" "uuid", "p_starts_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_actor_type" "text", "p_actor_id" "uuid", "p_reason" "text", "p_restores_grant_id" "uuid", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."grant_entitlement"("p_user_id" "uuid", "p_product_version_id" "uuid", "p_source_type" "text", "p_source_id" "uuid", "p_starts_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_actor_type" "text", "p_actor_id" "uuid", "p_reason" "text", "p_restores_grant_id" "uuid", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_user_application_entitlements"("p_user_id" "uuid", "p_application_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_user_application_entitlements"("p_user_id" "uuid", "p_application_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_user_application_memberships"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_user_application_memberships"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."publish_product_version"("p_product_version_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."publish_product_version"("p_product_version_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."receive_payment_webhook_event"("p_payment_id" "uuid", "p_order_id" "uuid", "p_provider" "text", "p_external_event_id" "text", "p_event_type" "text", "p_currency" "text", "p_amount" bigint, "p_payload_summary" "jsonb", "p_occurred_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."receive_payment_webhook_event"("p_payment_id" "uuid", "p_order_id" "uuid", "p_provider" "text", "p_external_event_id" "text", "p_event_type" "text", "p_currency" "text", "p_amount" bigint, "p_payload_summary" "jsonb", "p_occurred_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_paid_after_cancelled_order"("p_payment_event_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_paid_after_cancelled_order"("p_payment_event_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."redeem_application_code"("p_code_hash" "text", "p_user_id" "uuid", "p_application_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_ip_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."redeem_application_code"("p_code_hash" "text", "p_user_id" "uuid", "p_application_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_ip_hash" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."redeem_code"("p_code_hash" "text", "p_user_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_ip_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."redeem_code"("p_code_hash" "text", "p_user_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_ip_hash" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."refund_order_item"("p_order_item_id" "uuid", "p_amount" bigint, "p_mode" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."refund_order_item"("p_order_item_id" "uuid", "p_amount" bigint, "p_mode" "text", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."request_account_deletion"("p_user_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_account_deletion"("p_user_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."resolve_admin_membership"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_admin_membership"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."resolve_app_origin"("p_origin" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_app_origin"("p_origin" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_app_origin"("p_origin" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."resolve_application_context"("p_user_id" "uuid", "p_client_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_application_context"("p_user_id" "uuid", "p_client_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."restore_entitlement"("p_grant_id" "uuid", "p_actor_id" "uuid", "p_reason" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."restore_entitlement"("p_grant_id" "uuid", "p_actor_id" "uuid", "p_reason" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."retire_product_version"("p_product_version_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."retire_product_version"("p_product_version_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."revoke_entitlement"("p_grant_id" "uuid", "p_actor_type" "text", "p_actor_id" "uuid", "p_reason" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_entitlement"("p_grant_id" "uuid", "p_actor_type" "text", "p_actor_id" "uuid", "p_reason" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."run_retention_cleanup"("p_security_context_before" timestamp with time zone, "p_idempotency_response_before" timestamp with time zone, "p_batch_size" integer, "p_dry_run" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."run_retention_cleanup"("p_security_context_before" timestamp with time zone, "p_idempotency_response_before" timestamp with time zone, "p_batch_size" integer, "p_dry_run" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_current_product_version"("p_product_id" "uuid", "p_product_version_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_current_product_version"("p_product_id" "uuid", "p_product_version_id" "uuid") TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







