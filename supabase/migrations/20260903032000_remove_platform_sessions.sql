-- R1-T005: the target platform has no shared Cookie Session or CSRF session
-- table. OAuth access tokens and application context are the authentication
-- boundary; application-local BFF sessions are outside this database model.

drop function if exists public.create_platform_session(uuid, text, text, timestamptz);
drop function if exists public.get_platform_session(text);
drop function if exists public.revoke_platform_session(text, text);
drop function if exists public.revoke_all_platform_sessions(uuid, text);
drop function if exists public.verify_platform_csrf(text, text);
drop function if exists public.rotate_platform_csrf(text, text);
drop function if exists public.get_admin_session(text);

drop table if exists platform.platform_sessions;
