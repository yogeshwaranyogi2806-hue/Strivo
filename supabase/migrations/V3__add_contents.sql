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
