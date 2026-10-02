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
