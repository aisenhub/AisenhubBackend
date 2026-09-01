-- Identity profile data is platform-owned and remains outside the exposed Data API.

create table platform.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  locale text,
  status text not null default 'active',
  deleted_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint profiles_status_check
    check (status in ('active', 'disabled', 'deletion_pending', 'deleted')),
  constraint profiles_deleted_at_consistency_check
    check ((status = 'deleted') = (deleted_at is not null)),
  constraint profiles_display_name_nonempty_check
    check (display_name is null or btrim(display_name) <> ''),
  constraint profiles_locale_format_check
    check (locale is null or locale ~ '^[A-Za-z]{2}(-[A-Za-z0-9]{2,8})?$')
);

comment on table platform.profiles is
  'Platform-owned user profile metadata; authentication credentials remain in Supabase Auth.';

comment on column platform.profiles.id is
  'Immutable one-to-one reference to auth.users.id.';

comment on column platform.profiles.status is
  'Account lifecycle only; it is not a product role or entitlement.';

create index profiles_status_idx on platform.profiles (status);
create index profiles_created_at_idx on platform.profiles (created_at);

create or replace function platform.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, platform
as $$
begin
  insert into platform.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

comment on function platform.handle_new_auth_user() is
  'Controlled Auth-to-profile lifecycle hook; creates the platform profile after an Auth user is inserted.';

create trigger on_auth_user_created_create_profile
after insert on auth.users
for each row
execute function platform.handle_new_auth_user();

create or replace function platform.prevent_profile_identity_change()
returns trigger
language plpgsql
set search_path = pg_catalog, platform
as $$
begin
  if new.id <> old.id then
    raise exception 'profile identity is immutable'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger profiles_prevent_identity_change
before update on platform.profiles
for each row
execute function platform.prevent_profile_identity_change();

create trigger profiles_set_updated_at
before update on platform.profiles
for each row
execute function platform.set_updated_at();

alter table platform.profiles enable row level security;

insert into platform.profiles (id)
select id from auth.users
on conflict (id) do nothing;

revoke all on table platform.profiles from public, anon, authenticated, service_role;
revoke all on function platform.handle_new_auth_user() from public, anon, authenticated, service_role;
revoke all on function platform.prevent_profile_identity_change() from public, anon, authenticated, service_role;
