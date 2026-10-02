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
