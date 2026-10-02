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
