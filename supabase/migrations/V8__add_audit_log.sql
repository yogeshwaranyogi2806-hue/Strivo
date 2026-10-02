-- V8: Audit log
--
-- Records what people actually did in the app (signed in, created a
-- workspace, ...). Complements the on-device log file: this survives an
-- uninstall and can be queried across coaches and students.
--
-- Integrity note: there is deliberately NO insert policy and NO insert grant on
-- public.audit_log. The only write path is public.record_audit_event(), which
-- derives the actor from the caller's own session. A client cannot write an
-- entry that appears to come from another user.

create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  organization_id uuid references public.organizations(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_role text,
  event_name text not null check (length(trim(event_name)) between 1 and 100),
  detail jsonb not null default '{}'::jsonb,
  client_session_id text check (length(client_session_id) <= 64),
  occurred_at timestamptz not null default now()
);

create index if not exists audit_log_org_idx
  on public.audit_log (organization_id, occurred_at desc);
create index if not exists audit_log_actor_idx
  on public.audit_log (actor_user_id, occurred_at desc);
create index if not exists audit_log_event_idx
  on public.audit_log (event_name, occurred_at desc);

alter table public.audit_log enable row level security;

-- Read only. Writes go through the function below.
grant select on public.audit_log to authenticated;

drop policy if exists "Coaches can read the audit log" on public.audit_log;
create policy "Coaches can read the audit log"
on public.audit_log for select to authenticated
  using (private.is_org_coach(organization_id));

drop policy if exists "Users can read their own audit entries" on public.audit_log;
create policy "Users can read their own audit entries"
on public.audit_log for select to authenticated
  using (actor_user_id = (select auth.uid()));

-- Parameters are prefixed because plpgsql cannot tell a parameter from a
-- column of the same name.
--
-- organization_id is resolved from the caller's earliest membership rather than
-- accepted from the client, so a caller cannot file an entry against an
-- organization they do not belong to.
create or replace function public.record_audit_event(
  p_event text,
  p_detail jsonb default '{}'::jsonb,
  p_session text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_organization_id uuid;
  resolved_role text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if p_event is null or length(trim(p_event)) not between 1 and 100 then
    raise exception 'Event name must be between 1 and 100 characters';
  end if;

  select om.organization_id, om.role
    into resolved_organization_id, resolved_role
  from public.organization_memberships as om
  where om.user_id = (select auth.uid())
  order by om.created_at
  limit 1;

  insert into public.audit_log (
    organization_id,
    actor_user_id,
    actor_role,
    event_name,
    detail,
    client_session_id
  ) values (
    resolved_organization_id,
    (select auth.uid()),
    resolved_role,
    trim(p_event),
    coalesce(p_detail, '{}'::jsonb),
    nullif(left(p_session, 64), '')
  );
end;
$$;

revoke all on function public.record_audit_event(text, jsonb, text) from public;
grant execute on function public.record_audit_event(text, jsonb, text) to authenticated;

-- Retention: this table grows without bound. Prune entries older than the
-- pilot window before going live, e.g.
--   delete from public.audit_log where occurred_at < now() - interval '180 days';