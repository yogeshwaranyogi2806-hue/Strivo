-- V9: Invitations
--
-- Nobody self-registers. An existing admin generates an invite, sends it to
-- the person, and that person opens the app, enters the code, and fills in
-- their own details. The same flow adds another admin or a student.
--
-- Because creating an invite requires an existing admin, the very first
-- workspace cannot be invited into it. Bootstrap it once by hand -- see the
-- instructions at the bottom of this file.

create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  token text not null unique check (length(trim(token)) between 16 and 64),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  role text not null check (role in ('owner', 'coach', 'student')),
  email text,
  full_name text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted_at timestamptz,
  accepted_by uuid references auth.users(id) on delete set null,
  unique (organization_id, id),
  -- The inviter must hold a membership in the same organization, so an invite
  -- can never be recorded against a studio the creator does not belong to.
  foreign key (organization_id, created_by)
    references public.organization_memberships (organization_id, id)
);

create index if not exists invitations_org_idx
  on public.invitations (organization_id, created_at desc);
create index if not exists invitations_pending_idx
  on public.invitations (organization_id) where accepted_at is null;

-- Link the auth login to the student record. Existing student rows stay null:
-- they were created by a coach, not by an invite, and are linked by the coach
-- or backfilled by hand.
alter table public.students
  add column if not exists membership_id uuid references public.organization_memberships(id) on delete set null;

create unique index if not exists students_membership_idx
  on public.students (membership_id) where membership_id is not null;

alter table public.invitations enable row level security;

-- Read only. Every write goes through the functions below.
grant select on public.invitations to authenticated;

drop policy if exists "Coaches can read invitations" on public.invitations;
create policy "Coaches can read invitations"
on public.invitations for select to authenticated
  using (private.is_org_coach(organization_id));


-- Lets the recipient check a code before creating an account. Callable by anon
-- because nobody is signed in at that point; it exposes only the role, the
-- studio name and whether the code still works, and a 64-bit token cannot be
-- guessed in practice.
create or replace function public.invitation_details(p_token text)
returns table (
  role text,
  organization_name text,
  invited_email text,
  is_usable boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    inv.role,
    org.name,
    inv.email,
    (inv.accepted_at is null and inv.expires_at > now())
  from public.invitations as inv
  join public.organizations as org on org.id = inv.organization_id
  where inv.token = p_token;
$$;

revoke all on function public.invitation_details(text) from public;
grant execute on function public.invitation_details(text) to anon, authenticated;


-- Generates an invite for the caller's own organization.
create or replace function public.create_invitation(
  p_role text,
  p_email text default null,
  p_full_name text default null,
  p_expires_days integer default 14
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  inviter public.organization_memberships%rowtype;
  new_token text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if p_role is null or p_role not in ('owner', 'coach', 'student') then
    raise exception 'Role must be owner, coach or student';
  end if;

  if p_expires_days is null or p_expires_days < 1 or p_expires_days > 90 then
    raise exception 'Expiry must be between 1 and 90 days';
  end if;

  select * into inviter
  from public.organization_memberships as om
  where om.user_id = (select auth.uid())
    and private.is_org_coach(om.organization_id)
  order by om.created_at
  limit 1;

  if inviter.id is null then
    raise exception 'Only an existing admin can create invitations';
  end if;

  -- 8 random bytes, retried on the (vanishingly unlikely) collision.
  loop
    new_token := encode(gen_random_bytes(8), 'hex');
    exit when not exists (
      select 1 from public.invitations where token = new_token
    );
  end loop;

  insert into public.invitations (
    organization_id, role, email, full_name, created_by, expires_at
  ) values (
    inviter.organization_id,
    p_role,
    nullif(trim(p_email), ''),
    nullif(trim(p_full_name), ''),
    inviter.id,
    now() + make_interval(days => p_expires_days)
  );

  return new_token;
end;
$$;

revoke all on function public.create_invitation(text, text, text, integer) from public;
grant execute on function public.create_invitation(text, text, text, integer) to authenticated;


-- Redeems an invite. Must run AFTER the person has created their login, because
-- it is this function that grants the membership.
create or replace function public.accept_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  inv public.invitations%rowtype;
  caller_id uuid;
  caller_email text;
  person_name text;
  new_membership_id uuid;
  candidate_name text;
  linked_student_id uuid;
  name_matches integer;
begin
  caller_id := (select auth.uid());
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  select * into inv
  from public.invitations
  where token = p_token;

  if not found then
    raise exception 'That invitation code is not valid';
  end if;

  if inv.accepted_at is not null then
    raise exception 'That invitation has already been used';
  end if;

  if inv.expires_at <= now() then
    raise exception 'That invitation has expired';
  end if;

  select coalesce(u.email, ''), coalesce(nullif(p.full_name, ''), '')
    into caller_email, person_name
  from auth.users as u
  left join public.profiles as p on p.id = u.id
  where u.id = caller_id;

  -- An invite addressed to a specific mailbox cannot be redeemed by another.
  if inv.email is not null and lower(inv.email) <> lower(caller_email) then
    raise exception 'This invitation was issued to a different email address';
  end if;

  if exists (
    select 1 from public.organization_memberships
    where organization_id = inv.organization_id and user_id = caller_id
  ) then
    raise exception 'You already belong to this studio';
  end if;

  insert into public.organization_memberships (organization_id, user_id, role)
  values (inv.organization_id, caller_id, inv.role)
  returning id into new_membership_id;

  -- The membership id links the auth login to the student record. Without it a
  -- signed-in student cannot be matched to their own row, so every leave,
  -- submission and payment insert would have nothing to attach to.
  if inv.role = 'student' then
    candidate_name := coalesce(nullif(person_name, ''), nullif(caller_email, ''), 'Student');

    -- A coach may have created the student record already, before the person
    -- ever signed up. Link that row instead of creating a duplicate, otherwise
    -- one child ends up with two student records and their attendance and
    -- history split across both.
    --
    -- Matching is by name because that is the only field a coach entered. It is
    -- only applied when the match is unambiguous: if a studio has two unlinked
    -- students called "Aarav", guessing would attach the account to the wrong
    -- child, so a second record is created and a coach links it by hand.
    select count(*) into name_matches
    from public.students as s
    where s.organization_id = inv.organization_id
      and s.membership_id is null
      and lower(s.full_name) = lower(candidate_name);

    if name_matches = 1 then
      select s.id into linked_student_id
      from public.students as s
      where s.organization_id = inv.organization_id
        and s.membership_id is null
        and lower(s.full_name) = lower(candidate_name);
    end if;

    if linked_student_id is not null then
      update public.students
      set membership_id = new_membership_id
      where id = linked_student_id;
    else
      insert into public.students (organization_id, full_name, membership_id)
      values (inv.organization_id, candidate_name, new_membership_id);
    end if;
  end if;

  update public.invitations
  set accepted_at = now(), accepted_by = caller_id
  where id = inv.id;

  return inv.organization_id;
end;
$$;

revoke all on function public.accept_invitation(text) from public;
grant execute on function public.accept_invitation(text) to authenticated;

-- ============================================================
-- BOOTSTRAP: the first admin
-- ============================================================
-- There is no admin to send the first invitation, so the very first account has
-- to create a studio by hand.
--
-- The intended way is the app itself:
--
--   1. Supabase dashboard > Authentication > Users > Add user
--      (tick "Auto Confirm User" so the account can sign in immediately)
--
--   2. Sign in to the app with that account. It lands on the no-workspace
--      screen, which offers "Create your studio" because this function says
--      there is no admin yet.
--
-- public.create_coach_workspace(text) reads auth.uid(), so it must be called
-- over PostgREST with a real session -- running it from the SQL Editor fails
-- with 'Authentication required', because the editor has no logged-in user.
-- deployment_needs_bootstrap() is what lets the app decide whether to offer
-- the button.
--
-- If you would rather do it entirely in SQL, run the fallback below instead.
-- It takes an explicit email address so it does not depend on auth.uid():
--
--   select public.bootstrap_workspace_for(
--     'coach@example.com',
--     'Your Studio Name'
--   );
create or replace function public.deployment_needs_bootstrap()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1
    from public.organization_memberships
    where role in ('owner', 'coach')
  );
$$;

revoke all on function public.deployment_needs_bootstrap() from public;
grant execute on function public.deployment_needs_bootstrap() to anon, authenticated;

-- Only callable by the SQL editor / service_role, never over PostgREST, so it
-- cannot be used to claim ownership of somebody else's account.
create or replace function public.bootstrap_workspace_for(
  coach_email text,
  workspace_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  coach_id uuid;
  new_organization_id uuid;
begin
  if (select auth.role()) = 'service_role' then
    raise exception 'Use the SQL editor: service_role cannot bootstrap';
  end if;

  select u.id into coach_id
  from auth.users as u
  where lower(u.email) = lower(trim(coach_email))
  limit 1;

  if coach_id is null then
    raise exception 'No auth user with that email';
  end if;

  insert into public.organizations (name, created_by)
  values (trim(workspace_name), coach_id)
  returning id into new_organization_id;

  insert into public.organization_memberships (organization_id, user_id, role)
  values (new_organization_id, coach_id, 'owner');

  return new_organization_id;
end;
$$;

revoke all on function public.bootstrap_workspace_for(text, text) from public;

-- Retention: single-use invites are dead weight once accepted or long expired.
--   delete from public.invitations
--     where accepted_at is not null and accepted_at < now() - interval '90 days';