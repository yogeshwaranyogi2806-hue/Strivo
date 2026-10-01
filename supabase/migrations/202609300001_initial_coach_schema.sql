create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  created_at timestamptz not null default now()
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 100),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.organization_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'coach', 'student', 'parent')),
  created_at timestamptz not null default now(),
  unique (organization_id, user_id),
  unique (organization_id, id)
);

create index organization_memberships_user_idx
  on public.organization_memberships (user_id, organization_id);

create function private.is_org_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_memberships as membership
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
  );
$$;

create function private.is_org_coach(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_memberships as membership
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.role in ('owner', 'coach')
  );
$$;

revoke all on function private.is_org_member(uuid) from public;
revoke all on function private.is_org_coach(uuid) from public;
grant execute on function private.is_org_member(uuid) to authenticated;
grant execute on function private.is_org_coach(uuid) to authenticated;

create function public.create_coach_workspace(workspace_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_organization_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if workspace_name is null or length(trim(workspace_name)) not between 2 and 100 then
    raise exception 'Workspace name must be between 2 and 100 characters';
  end if;

  insert into public.organizations (name, created_by)
  values (trim(workspace_name), (select auth.uid()))
  returning id into new_organization_id;

  insert into public.organization_memberships (organization_id, user_id, role)
  values (new_organization_id, (select auth.uid()), 'owner');

  return new_organization_id;
end;
$$;

revoke all on function public.create_coach_workspace(text) from public;
grant execute on function public.create_coach_workspace(text) to authenticated;

create function private.create_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.phone
  )
  on conflict (id) do update set phone = excluded.phone;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.create_profile_for_auth_user();

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 100),
  schedule text not null default '',
  coach_membership_id uuid not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, coach_membership_id)
    references public.organization_memberships (organization_id, id)
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 1 and 120),
  joined_on date not null default current_date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, id)
);

create table public.class_enrollments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  class_id uuid not null,
  student_id uuid not null,
  enrolled_on date not null default current_date,
  ended_on date,
  created_at timestamptz not null default now(),
  unique (class_id, student_id),
  unique (organization_id, class_id, student_id),
  foreign key (organization_id, class_id)
    references public.classes (organization_id, id),
  foreign key (organization_id, student_id)
    references public.students (organization_id, id),
  check (ended_on is null or ended_on >= enrolled_on)
);

create table public.skills (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 100),
  category text not null default 'General',
  description text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, name)
);

create table public.assessments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  student_id uuid not null,
  skill_id uuid not null,
  coach_membership_id uuid not null,
  class_id uuid,
  score smallint not null check (score between 1 and 5),
  coach_note text not null default '',
  assessed_on date not null default current_date,
  created_at timestamptz not null default now(),
  foreign key (organization_id, student_id)
    references public.students (organization_id, id),
  foreign key (organization_id, skill_id)
    references public.skills (organization_id, id),
  foreign key (organization_id, coach_membership_id)
    references public.organization_memberships (organization_id, id),
  foreign key (organization_id, class_id)
    references public.classes (organization_id, id)
);

create index assessments_student_history_idx
  on public.assessments (organization_id, student_id, assessed_on desc);
create index assessments_skill_history_idx
  on public.assessments (organization_id, skill_id, assessed_on desc);

create table public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  class_id uuid not null,
  coach_membership_id uuid not null,
  session_date date not null default current_date,
  note text not null default '',
  created_at timestamptz not null default now(),
  unique (organization_id, id, class_id),
  foreign key (organization_id, class_id)
    references public.classes (organization_id, id),
  foreign key (organization_id, coach_membership_id)
    references public.organization_memberships (organization_id, id)
);

create table public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  session_id uuid not null,
  class_id uuid not null,
  student_id uuid not null,
  status text not null check (status in ('present', 'absent', 'late', 'excused')),
  note text not null default '',
  created_at timestamptz not null default now(),
  unique (session_id, student_id),
  foreign key (organization_id, session_id, class_id)
    references public.attendance_sessions (organization_id, id, class_id),
  foreign key (organization_id, class_id, student_id)
    references public.class_enrollments (organization_id, class_id, student_id)
);

alter table public.profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.classes enable row level security;
alter table public.students enable row level security;
alter table public.class_enrollments enable row level security;
alter table public.skills enable row level security;
alter table public.assessments enable row level security;
alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;

grant select, update on public.profiles to authenticated;
grant select on public.organizations to authenticated;
grant select on public.organization_memberships to authenticated;
grant select, insert, update, delete on
  public.classes,
  public.students,
  public.class_enrollments,
  public.skills,
  public.assessments,
  public.attendance_sessions,
  public.attendance_records
to authenticated;

create policy "Users can read their own profile"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy "Users can update their own profile"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "Members can read their organizations"
  on public.organizations for select to authenticated
  using (private.is_org_member(id));

create policy "Users can read their memberships"
  on public.organization_memberships for select to authenticated
  using (user_id = (select auth.uid()) or private.is_org_coach(organization_id));

create policy "Coaches can read classes"
  on public.classes for select to authenticated
  using (private.is_org_coach(organization_id));
create policy "Coaches can manage classes"
  on public.classes for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

create policy "Coaches can read students"
  on public.students for select to authenticated
  using (private.is_org_coach(organization_id));
create policy "Coaches can manage students"
  on public.students for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

create policy "Coaches can read class enrollments"
  on public.class_enrollments for select to authenticated
  using (private.is_org_coach(organization_id));
create policy "Coaches can manage class enrollments"
  on public.class_enrollments for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

create policy "Coaches can read skills"
  on public.skills for select to authenticated
  using (private.is_org_coach(organization_id));
create policy "Coaches can manage skills"
  on public.skills for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

create policy "Coaches can read assessments"
  on public.assessments for select to authenticated
  using (private.is_org_coach(organization_id));
create policy "Coaches can manage assessments"
  on public.assessments for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

create policy "Coaches can read attendance sessions"
  on public.attendance_sessions for select to authenticated
  using (private.is_org_coach(organization_id));
create policy "Coaches can manage attendance sessions"
  on public.attendance_sessions for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

create policy "Coaches can read attendance records"
  on public.attendance_records for select to authenticated
  using (private.is_org_coach(organization_id));
create policy "Coaches can manage attendance records"
  on public.attendance_records for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));