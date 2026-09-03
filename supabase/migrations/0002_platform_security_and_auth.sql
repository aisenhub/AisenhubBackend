-- Clean baseline security boundary and the only Auth-to-platform lifecycle hook.

revoke all on schema platform from public, anon, authenticated, service_role;
alter default privileges in schema platform
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges in schema platform
  revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges in schema platform
  revoke all on functions from public, anon, authenticated, service_role;
revoke all on all tables in schema platform from public, anon, authenticated, service_role;
revoke all on all sequences in schema platform from public, anon, authenticated, service_role;
revoke all on all functions in schema platform from public, anon, authenticated, service_role;

-- Supabase's default public-schema grants are direct grants, so revoking PUBLIC
-- alone is insufficient for a clean rebuild.
revoke all on all functions in schema public from anon, authenticated;
revoke all on function public.get_public_products() from service_role;
revoke all on function public.get_public_app(text) from service_role;
revoke all on function public.resolve_app_origin(text) from service_role;
revoke all on function public.current_profile() from service_role;
grant execute on function public.get_public_products() to anon, authenticated;
grant execute on function public.get_public_app(text) to anon, authenticated;
grant execute on function public.resolve_app_origin(text) to anon, authenticated;
grant execute on function public.current_profile() to authenticated;

create trigger on_auth_user_created_create_profile
after insert on auth.users
for each row
execute function platform.handle_new_auth_user();
