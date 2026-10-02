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
