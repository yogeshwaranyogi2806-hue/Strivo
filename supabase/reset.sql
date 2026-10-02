-- Strivo - full reset
-- DESTRUCTIVE. Removes every Strivo table, policy and function so
-- apply_all.sql can be re-applied from scratch.
--
-- Does NOT touch auth.users: everybody keeps their login, you just lose the
-- studios, students, invites and records.
--
-- Also does NOT touch Supabase's own objects (auth, storage, realtime, graphql,
-- vault). Only the public and private schemas are cleared.
--
-- After running this you MUST run apply_all.sql again, then create the first
-- studio from the app.

\echo '--- objects that will be removed ---'

do $$
declare
  r          record;
  tbl_count  int;
  fn_count   int;
  pol_count  int;
begin
  -- The profile trigger on auth.users depends on
  -- private.create_profile_for_auth_user(), so it has to go first or the
  -- function drop below fails with "other objects depend on it".
  if to_regclass('auth.users') is not null then
    execute 'drop trigger if exists on_auth_user_created on auth.users';
  end if;

  select count(*) into tbl_count from information_schema.tables
   where table_schema in ('public', 'private') and table_type = 'BASE TABLE';
  select count(*) into fn_count from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private');
  select count(*) into pol_count from pg_policies
   where schemaname in ('public', 'private');

  raise notice 'tables: %, functions: %, policies: %', tbl_count, fn_count, pol_count;
  raise notice 'data rows to be destroyed: organizations=%, memberships=%, students=%, invites=%',
    (select count(*) from public.organizations),
    (select count(*) from public.organization_memberships),
    (select count(*) from public.students),
    (select count(*) from public.invitations);

  for r in
    select table_schema, table_name
      from information_schema.tables
     where table_schema in ('public', 'private') and table_type = 'BASE TABLE'
  loop
    raise notice 'drop table % %', r.table_schema, r.table_name;
    execute format('drop table if exists %I.%I cascade', r.table_schema, r.table_name);
  end loop;

  -- Functions after tables: some overloads share a name and dropping the wrong
  -- order leaves stragglers. pg_get_function_identity_arguments gives the exact
  -- (text,text,uuid) signature the drop needs.
  for r in
    select n.nspname as schema_name,
           p.proname,
           pg_get_function_identity_arguments(p.oid) as args
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private')
       -- Skip functions owned by an extension (pgcrypto's digest, hmac, ...).
       -- Postgres refuses to drop those: "cannot drop function digest because
       -- extension pgcrypto requires it".
       and not exists (
         select 1
           from pg_depend d
          where d.objid = p.oid
            and d.classid = 'pg_proc'::regclass
            and d.deptype = 'e'
       )
  loop
    -- A space after % keeps the next literal ("(") from being read as another
    -- placeholder. RAISE has no positional %1/%2 form: '%.%(%' counts four
    -- placeholders and fails with "too few parameters".
    raise notice 'drop function % % (%)', r.schema_name, r.proname, r.args;
    execute format('drop function if exists %I.%I(%s) cascade', r.schema_name, r.proname, r.args);
  end loop;

  drop schema if exists private cascade;
end;
$$;

\echo '--- reset complete: now run apply_all.sql ---'