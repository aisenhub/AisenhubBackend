begin;

select plan(9);

select ok(
  to_regclass('platform.platform_sessions') is null,
  'shared Platform Session table is absent from the target schema'
);
select ok(
  to_regprocedure('public.create_platform_session(uuid,text,text,timestamptz)') is null,
  'session exchange database function is absent'
);
select ok(
  to_regprocedure('public.get_platform_session(text)') is null,
  'session read database function is absent'
);
select ok(
  to_regprocedure('public.revoke_platform_session(text,text)') is null,
  'session revoke database function is absent'
);
select ok(
  to_regprocedure('public.revoke_all_platform_sessions(uuid,text)') is null,
  'bulk session revoke database function is absent'
);
select ok(
  to_regprocedure('public.verify_platform_csrf(text,text)') is null,
  'session-bound CSRF verification function is absent'
);
select ok(
  to_regprocedure('public.rotate_platform_csrf(text,text)') is null,
  'session-bound CSRF rotation function is absent'
);
select ok(
  to_regprocedure('public.get_admin_session(text)') is null,
  'Admin session database function is absent'
);
select ok(
  not exists (
    select 1
      from pg_proc
     where prosrc ilike '%platform_sessions%'
  ),
  'no database function body references the removed session table'
);

select * from finish();
rollback;
