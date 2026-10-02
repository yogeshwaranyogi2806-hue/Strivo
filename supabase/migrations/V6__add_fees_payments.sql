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
