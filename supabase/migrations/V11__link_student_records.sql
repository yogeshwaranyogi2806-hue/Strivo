-- V11: Let a coach link a student record to a login
--
-- V9 links students.membership_id automatically when an invite is redeemed,
-- by matching the name the student typed against a coach-created row. That
-- covers almost everyone, but two cases still need a human:
--
--   1. The name the student typed does not match what the coach entered.
--   2. A studio has two unlinked students with the same name, so the automatic
--      match was refused as ambiguous.
--
-- In both cases the student signs in fine but sees "your studio has not linked
-- your login to a student record yet". This gives the coach a way to fix that
-- by hand. It is a link, not a merge: the student record keeps its id, so
-- attendance, fees and history already recorded against it stay where they are.

-- Returns the unlinked student records and the unlinked student logins in the
-- caller's own studio, so a coach can see both sides of the mismatch.
create or replace function public.unlinked_student_records()
returns table (
  student_id uuid,
  student_name text,
  membership_id uuid,
  student_email text
)
language sql
stable
security definer
set search_path = ''
as $$
  with org as (
    select m.organization_id
    from public.organization_memberships as m
    where m.user_id = (select auth.uid())
      and m.role in ('owner', 'coach')
    limit 1
  )
  -- Each branch needs its own parentheses once one of them has an ORDER BY:
  -- Postgres rejects "select ... order by ... union all select ...".
  -- student_email is null here on purpose: this branch is only rows that have
  -- no login attached yet.
  (
    select
      s.id,
      s.full_name,
      s.membership_id,
      null::text
    from public.students as s
    join org on org.organization_id = s.organization_id
    where s.membership_id is null
    order by s.full_name
  )
  union all
  (
    select
      null::uuid,
      null::text,
      m.id,
      u.email
    from public.organization_memberships as m
    join org on org.organization_id = m.organization_id
    join auth.users as u on u.id = m.user_id
    where m.role = 'student'
      and not exists (
        select 1 from public.students as s
        where s.membership_id = m.id
      )
  )
$$;

-- Attaches a login to a student record. Both must already be in the caller's
-- own studio, so this cannot reach across organizations. The unique index on
-- students.membership_id stops a login being attached to two students.
create or replace function public.link_student_record(p_student_id uuid, p_membership_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_org uuid;
  target_student_org uuid;
  target_membership_org uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select m.organization_id into caller_org
  from public.organization_memberships as m
  where m.user_id = (select auth.uid())
    and m.role in ('owner', 'coach')
  limit 1;

  if caller_org is null then
    raise exception 'Only a coach can link a student record';
  end if;

  if p_student_id is null or p_membership_id is null then
    raise exception 'Both a student record and a login are required';
  end if;

  select s.organization_id into target_student_org
  from public.students as s
  where s.id = p_student_id;

  select m.organization_id into target_membership_org
  from public.organization_memberships as m
  where m.id = p_membership_id and m.role = 'student';

  if target_student_org is null or target_student_org <> caller_org then
    raise exception 'That student record is not in your studio';
  end if;

  if target_membership_org is null or target_membership_org <> caller_org then
    raise exception 'That login is not a student in your studio';
  end if;

  -- Refuse rather than silently move a record that is already claimed.
  if exists (
    select 1 from public.students
    where membership_id = p_membership_id and id <> p_student_id
  ) then
    raise exception 'That login is already linked to another student record';
  end if;

  update public.students
  set membership_id = p_membership_id
  where id = p_student_id and membership_id is null;

  if not found then
    raise exception 'That student record is already linked, or no longer exists';
  end if;

  return true;
end;
$$;

revoke all on function public.unlinked_student_records() from public;
revoke all on function public.link_student_record(uuid, uuid) from public;
grant execute on function public.unlinked_student_records() to authenticated;
grant execute on function public.link_student_record(uuid, uuid) to authenticated;