-- Strivo - consolidated migrations V1 through V11
-- Run in Supabase Dashboard > SQL Editor.
--
-- Safe to run more than once: every statement is guarded (CREATE TABLE/INDEX/
-- COLUMN IF NOT EXISTS, CREATE OR REPLACE FUNCTION, DROP POLICY IF EXISTS
-- before CREATE POLICY). Re-running converges the schema rather than failing
-- with "relation already exists".
--
-- It does NOT delete existing rows, so re-running will not wipe a studio. If you
-- want a genuinely clean slate, drop the tables by hand first.

-- ============================================================
-- V1__initial_coach_schema.sql
-- ============================================================
create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  created_at timestamptz not null default now()
);

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 100),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.organization_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'coach', 'student', 'parent')),
  created_at timestamptz not null default now(),
  unique (organization_id, user_id),
  unique (organization_id, id)
);

create index if not exists organization_memberships_user_idx
  on public.organization_memberships (user_id, organization_id);

create or replace function private.is_org_member(target_organization_id uuid)
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

create or replace function private.is_org_coach(target_organization_id uuid)
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

create or replace function public.create_coach_workspace(workspace_name text)
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

create or replace function private.create_profile_for_auth_user()
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

-- Postgres has no CREATE TRIGGER IF NOT EXISTS, so drop first. Without this a
-- re-run fails with 'trigger already exists'.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.create_profile_for_auth_user();

create table if not exists public.classes (
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

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 1 and 120),
  joined_on date not null default current_date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, id)
);

create table if not exists public.class_enrollments (
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

create table if not exists public.skills (
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

create table if not exists public.assessments (
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

create index if not exists assessments_student_history_idx
  on public.assessments (organization_id, student_id, assessed_on desc);
create index if not exists assessments_skill_history_idx
  on public.assessments (organization_id, skill_id, assessed_on desc);

create table if not exists public.attendance_sessions (
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

create table if not exists public.attendance_records (
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

drop policy if exists "Users can read their own profile" on public.profiles;
create policy "Users can read their own profile"
on public.profiles for select to authenticated
  using (id = (select auth.uid()));
drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists "Members can read their organizations" on public.organizations;
create policy "Members can read their organizations"
on public.organizations for select to authenticated
  using (private.is_org_member(id));

drop policy if exists "Users can read their memberships" on public.organization_memberships;
create policy "Users can read their memberships"
on public.organization_memberships for select to authenticated
  using (user_id = (select auth.uid()) or private.is_org_coach(organization_id));

drop policy if exists "Coaches can read classes" on public.classes;
create policy "Coaches can read classes"
on public.classes for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage classes" on public.classes;
create policy "Coaches can manage classes"
on public.classes for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

drop policy if exists "Coaches can read students" on public.students;
create policy "Coaches can read students"
on public.students for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage students" on public.students;
create policy "Coaches can manage students"
on public.students for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

drop policy if exists "Coaches can read class enrollments" on public.class_enrollments;
create policy "Coaches can read class enrollments"
on public.class_enrollments for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage class enrollments" on public.class_enrollments;
create policy "Coaches can manage class enrollments"
on public.class_enrollments for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

drop policy if exists "Coaches can read skills" on public.skills;
create policy "Coaches can read skills"
on public.skills for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage skills" on public.skills;
create policy "Coaches can manage skills"
on public.skills for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

drop policy if exists "Coaches can read assessments" on public.assessments;
create policy "Coaches can read assessments"
on public.assessments for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage assessments" on public.assessments;
create policy "Coaches can manage assessments"
on public.assessments for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

drop policy if exists "Coaches can read attendance sessions" on public.attendance_sessions;
create policy "Coaches can read attendance sessions"
on public.attendance_sessions for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage attendance sessions" on public.attendance_sessions;
create policy "Coaches can manage attendance sessions"
on public.attendance_sessions for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

drop policy if exists "Coaches can read attendance records" on public.attendance_records;
create policy "Coaches can read attendance records"
on public.attendance_records for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage attendance records" on public.attendance_records;
create policy "Coaches can manage attendance records"
on public.attendance_records for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));

-- ============================================================
-- V2__add_leaves.sql
-- ============================================================
-- V2: Student leave applications with approval workflow

create table if not exists public.leaves (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  student_id uuid not null,
  membership_id uuid not null,
  start_date date not null,
  end_date date not null,
  reason text not null default '',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text not null default '',
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, student_id)
    references public.students (organization_id, id),
  foreign key (organization_id, membership_id)
    references public.organization_memberships (organization_id, id),
  foreign key (organization_id, reviewed_by)
    references public.organization_memberships (organization_id, id),
  check (end_date >= start_date)
);

create index if not exists leaves_student_idx
  on public.leaves (organization_id, student_id, created_at desc);
create index if not exists leaves_status_idx
  on public.leaves (organization_id, status);

alter table public.leaves enable row level security;

grant select, insert, update, delete on public.leaves to authenticated;

drop policy if exists "Coaches can read leaves" on public.leaves;
create policy "Coaches can read leaves"
on public.leaves for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage leaves" on public.leaves;
create policy "Coaches can manage leaves"
on public.leaves for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));
drop policy if exists "Students can read own leaves" on public.leaves;
create policy "Students can read own leaves"
on public.leaves for select to authenticated
  using (membership_id in (
    select id from public.organization_memberships
    where user_id = (select auth.uid()) and role = 'student'
  ));
drop policy if exists "Students can apply for leave" on public.leaves;
create policy "Students can apply for leave"
on public.leaves for insert to authenticated
  with check (membership_id in (
    select id from public.organization_memberships
    where user_id = (select auth.uid()) and role = 'student'
  ));


-- ============================================================
-- V3__add_contents.sql
-- ============================================================
-- V3: Content management and uploads for students

create table if not exists public.contents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  uploaded_by uuid not null,
  title text not null check (length(trim(title)) between 1 and 200),
  description text not null default '',
  content_type text not null default 'article' check (content_type in ('article', 'video', 'document', 'image')),
  file_url text,
  file_name text,
  file_size integer,
  is_published boolean not null default false,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, uploaded_by)
    references public.organization_memberships (organization_id, id)
);

create index if not exists contents_org_idx
  on public.contents (organization_id, is_published, published_at desc);

alter table public.contents enable row level security;

grant select, insert, update, delete on public.contents to authenticated;

drop policy if exists "Coaches can read contents" on public.contents;
create policy "Coaches can read contents"
on public.contents for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage contents" on public.contents;
create policy "Coaches can manage contents"
on public.contents for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));
drop policy if exists "Students can read published contents" on public.contents;
create policy "Students can read published contents"
on public.contents for select to authenticated
  using (
    is_published = true
    and organization_id in (
      select organization_id from public.organization_memberships
      where user_id = (select auth.uid())
    )
  );


-- ============================================================
-- V4__add_tasks.sql
-- ============================================================
-- V4: Tasks and demos assigned to students

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  class_id uuid,
  assigned_by uuid not null,
  title text not null check (length(trim(title)) between 1 and 200),
  description text not null default '',
  due_date date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, class_id)
    references public.classes (organization_id, id),
  foreign key (organization_id, assigned_by)
    references public.organization_memberships (organization_id, id)
);

create index if not exists tasks_class_idx
  on public.tasks (organization_id, class_id, is_active);

alter table public.tasks enable row level security;

grant select, insert, update, delete on public.tasks to authenticated;

drop policy if exists "Coaches can read tasks" on public.tasks;
create policy "Coaches can read tasks"
on public.tasks for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage tasks" on public.tasks;
create policy "Coaches can manage tasks"
on public.tasks for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));
drop policy if exists "Students can read tasks for their classes" on public.tasks;
create policy "Students can read tasks for their classes"
on public.tasks for select to authenticated
  using (
    class_id in (
      select class_id from public.class_enrollments ce
      join public.organization_memberships om
        on ce.organization_id = om.organization_id
      where om.user_id = (select auth.uid()) and om.role = 'student'
    )
  );

-- Task submissions from students

create table if not exists public.task_submissions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  task_id uuid not null,
  student_id uuid not null,
  membership_id uuid not null,
  submission_text text not null default '',
  file_url text,
  file_name text,
  submitted_at timestamptz not null default now(),
  reviewed_by uuid,
  review_note text not null default '',
  rating smallint check (rating between 1 and 5),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (organization_id, task_id, student_id),
  foreign key (organization_id, task_id)
    references public.tasks (organization_id, id),
  foreign key (organization_id, student_id)
    references public.students (organization_id, id),
  foreign key (organization_id, membership_id)
    references public.organization_memberships (organization_id, id),
  foreign key (organization_id, reviewed_by)
    references public.organization_memberships (organization_id, id)
);

create index if not exists task_submissions_task_idx
  on public.task_submissions (organization_id, task_id);
create index if not exists task_submissions_student_idx
  on public.task_submissions (organization_id, student_id);

alter table public.task_submissions enable row level security;

grant select, insert, update, delete on public.task_submissions to authenticated;

drop policy if exists "Coaches can read task submissions" on public.task_submissions;
create policy "Coaches can read task submissions"
on public.task_submissions for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage task submissions" on public.task_submissions;
create policy "Coaches can manage task submissions"
on public.task_submissions for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));
drop policy if exists "Students can read own submissions" on public.task_submissions;
create policy "Students can read own submissions"
on public.task_submissions for select to authenticated
  using (membership_id in (
    select id from public.organization_memberships
    where user_id = (select auth.uid()) and role = 'student'
  ));
drop policy if exists "Students can submit tasks" on public.task_submissions;
create policy "Students can submit tasks"
on public.task_submissions for insert to authenticated
  with check (membership_id in (
    select id from public.organization_memberships
    where user_id = (select auth.uid()) and role = 'student'
  ));


-- ============================================================
-- V5__add_announcements.sql
-- ============================================================
-- V5: Announcements published by admin for students

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  posted_by uuid not null,
  title text not null check (length(trim(title)) between 1 and 200),
  body text not null default '',
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  is_published boolean not null default false,
  published_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, posted_by)
    references public.organization_memberships (organization_id, id)
);

create index if not exists announcements_org_idx
  on public.announcements (organization_id, is_published, published_at desc);

alter table public.announcements enable row level security;

grant select, insert, update, delete on public.announcements to authenticated;

drop policy if exists "Coaches can read announcements" on public.announcements;
create policy "Coaches can read announcements"
on public.announcements for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage announcements" on public.announcements;
create policy "Coaches can manage announcements"
on public.announcements for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));
drop policy if exists "Students can read published announcements" on public.announcements;
create policy "Students can read published announcements"
on public.announcements for select to authenticated
  using (
    is_published = true
    and organization_id in (
      select organization_id from public.organization_memberships
      where user_id = (select auth.uid())
    )
  );


-- ============================================================
-- V6__add_fees_payments.sql
-- ============================================================
-- V6: Fee structure and payment records

create table if not exists public.fee_structures (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 100),
  amount numeric(10,2) not null check (amount >= 0),
  frequency text not null default 'monthly' check (frequency in ('one_time', 'monthly', 'quarterly', 'yearly')),
  description text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, name)
);

create index if not exists fee_structures_org_idx
  on public.fee_structures (organization_id, is_active);

alter table public.fee_structures enable row level security;

grant select, insert, update, delete on public.fee_structures to authenticated;

drop policy if exists "Coaches can read fee structures" on public.fee_structures;
create policy "Coaches can read fee structures"
on public.fee_structures for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage fee structures" on public.fee_structures;
create policy "Coaches can manage fee structures"
on public.fee_structures for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));
drop policy if exists "Students can read fee structures" on public.fee_structures;
create policy "Students can read fee structures"
on public.fee_structures for select to authenticated
  using (
    is_active = true
    and organization_id in (
      select organization_id from public.organization_memberships
      where user_id = (select auth.uid())
    )
  );

-- Payment records

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  student_id uuid not null,
  membership_id uuid not null,
  fee_structure_id uuid,
  amount numeric(10,2) not null check (amount > 0),
  payment_method text not null default 'cash' check (payment_method in ('cash', 'card', 'upi', 'bank_transfer', 'online')),
  status text not null default 'pending' check (status in ('pending', 'completed', 'failed', 'refunded')),
  transaction_id text not null default '',
  paid_at timestamptz,
  due_date date,
  note text not null default '',
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, student_id)
    references public.students (organization_id, id),
  foreign key (organization_id, membership_id)
    references public.organization_memberships (organization_id, id),
  foreign key (organization_id, fee_structure_id)
    references public.fee_structures (organization_id, id)
);

create index if not exists payments_student_idx
  on public.payments (organization_id, student_id, created_at desc);
create index if not exists payments_status_idx
  on public.payments (organization_id, status);

alter table public.payments enable row level security;

grant select, insert, update, delete on public.payments to authenticated;

drop policy if exists "Coaches can read payments" on public.payments;
create policy "Coaches can read payments"
on public.payments for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage payments" on public.payments;
create policy "Coaches can manage payments"
on public.payments for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));
drop policy if exists "Students can read own payments" on public.payments;
create policy "Students can read own payments"
on public.payments for select to authenticated
  using (membership_id in (
    select id from public.organization_memberships
    where user_id = (select auth.uid()) and role = 'student'
  ));


-- ============================================================
-- V7__add_feedback.sql
-- ============================================================
-- V7: Student suggestions and feedback

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  membership_id uuid not null,
  category text not null default 'general' check (category in ('general', 'content', 'coach', 'facility', 'suggestion', 'complaint')),
  subject text not null check (length(trim(subject)) between 1 and 200),
  message text not null check (length(trim(message)) between 1 and 5000),
  is_anonymous boolean not null default false,
  status text not null default 'open' check (status in ('open', 'in_review', 'resolved', 'closed')),
  reviewed_by uuid,
  review_note text not null default '',
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, membership_id)
    references public.organization_memberships (organization_id, id),
  foreign key (organization_id, reviewed_by)
    references public.organization_memberships (organization_id, id)
);

create index if not exists feedback_org_idx
  on public.feedback (organization_id, status, created_at desc);
create index if not exists feedback_member_idx
  on public.feedback (organization_id, membership_id);

alter table public.feedback enable row level security;

grant select, insert, update, delete on public.feedback to authenticated;

drop policy if exists "Coaches can read feedback" on public.feedback;
create policy "Coaches can read feedback"
on public.feedback for select to authenticated
  using (private.is_org_coach(organization_id));
drop policy if exists "Coaches can manage feedback" on public.feedback;
create policy "Coaches can manage feedback"
on public.feedback for all to authenticated
  using (private.is_org_coach(organization_id))
  with check (private.is_org_coach(organization_id));
drop policy if exists "Students can read own feedback" on public.feedback;
create policy "Students can read own feedback"
on public.feedback for select to authenticated
  using (membership_id in (
    select id from public.organization_memberships
    where user_id = (select auth.uid()) and role = 'student'
  ));
drop policy if exists "Students can submit feedback" on public.feedback;
create policy "Students can submit feedback"
on public.feedback for insert to authenticated
  with check (membership_id in (
    select id from public.organization_memberships
    where user_id = (select auth.uid()) and role = 'student'
  ));




-- ============================================================
-- V8__add_audit_log.sql
-- ============================================================
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

-- ============================================================
-- V9__add_invitations.sql
-- ============================================================
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

-- Retention: single-use invites are dead weight once accepted or long expired.
--   delete from public.invitations
--     where accepted_at is not null and accepted_at < now() - interval '90 days';

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
-- ============================================================
-- V10: Let students read their own records
-- ============================================================

-- V10: Let students read their own records
--
-- Up to here, every policy touching a student's own data was coach-only. A
-- signed-in student could not read their own student row, their attendance,
-- or anything keyed off their student id -- which makes a student dashboard
-- impossible to build without a back door. This adds only self-scoped read
-- policies. Nothing here lets a student see anybody else's rows, and no new
-- write access is granted.
--
-- Requires V9, which adds students.membership_id.

-- Resolves the signed-in student's own students row id. SECURITY DEFINER so it
-- can look up the row that the read policies themselves are guarding; it
-- returns only the caller's own id and never anybody else's.
create or replace function private.my_student_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id
  from public.students as s
  where s.membership_id in (
    select m.id
    from public.organization_memberships as m
    where m.user_id = (select auth.uid())
      and m.role = 'student'
  )
  limit 1
$$;

revoke all on function private.my_student_id() from public;
grant execute on function private.my_student_id() to authenticated;

-- The helper itself must not leak the student id to anon.
create or replace function private.my_membership_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id
  from public.organization_memberships as m
  where m.user_id = (select auth.uid())
    and m.role = 'student'
  limit 1
$$;

revoke all on function private.my_membership_id() from public;
grant execute on function private.my_membership_id() to authenticated;

-- A student can read their own student record. Needed to show their own name,
-- joined-on date and active flag in the app.
drop policy if exists "Students can read own student record" on public.students;
create policy "Students can read own student record"
on public.students for select to authenticated
  using (membership_id = (select private.my_membership_id()));

-- Attendance: a student can read their own records, and the sessions they belong
-- to (session notes may contain context such as "fixture cancelled").
drop policy if exists "Students can read own attendance records" on public.attendance_records;
create policy "Students can read own attendance records"
on public.attendance_records for select to authenticated
  using (student_id = (select private.my_student_id()));

drop policy if exists "Students can read own attendance sessions" on public.attendance_sessions;
create policy "Students can read own attendance sessions"
on public.attendance_sessions for select to authenticated
  using (class_id in (
    select ce.class_id
    from public.class_enrollments as ce
    where ce.student_id = (select private.my_student_id())
  ));

-- Class enrollments, so the app can name the classes a student is in.
drop policy if exists "Students can read own enrollments" on public.class_enrollments;
create policy "Students can read own enrollments"
on public.class_enrollments for select to authenticated
  using (student_id = (select private.my_student_id()));

-- Classes for enrolled students, so an enrollment can show a class name.
drop policy if exists "Students can read enrolled classes" on public.classes;
create policy "Students can read enrolled classes"
on public.classes for select to authenticated
  using (id in (
    select ce.class_id
    from public.class_enrollments as ce
    where ce.student_id = (select private.my_student_id())
  ));

-- Notes on this migration:
--
-- * public.students has no UPDATE policy for students. A student cannot edit
--   their own full_name through the API; profile name changes go through the
--   profiles table instead. This is deliberate and can be relaxed later.
-- * Nothing here grants a student write access to any table other than the
--   inserts already provided by V2 (leaves) and V4 (task_submissions).
-- * To link a coach-created student row to that student's login, set
--   students.membership_id to the matching organization_memberships.id.
-- ============================================================
-- V11: Let a coach link a student record to a login
-- ============================================================

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