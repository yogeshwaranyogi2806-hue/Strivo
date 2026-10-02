-- Strivo - schema status check
-- Read-only. Safe to run as often as you like.
-- Paste into Supabase Dashboard > SQL Editor and press Run.

-- Counted by name, not with a bare pg_proc total: the pgcrypto extension also
-- installs ~36 functions into public, so a raw count is misleading.
with wanted(fn) as (
  values ('private.create_profile_for_auth_user'), ('private.is_org_coach'),
         ('private.is_org_member'), ('private.my_membership_id'),
         ('private.my_student_id'), ('public.accept_invitation'),
         ('public.bootstrap_workspace_for'), ('public.create_coach_workspace'),
         ('public.create_invitation'), ('public.deployment_needs_bootstrap'),
         ('public.invitation_details'), ('public.link_student_record'),
         ('public.record_audit_event'), ('public.unlinked_student_records')
)
select 'strivo functions' as what, count(*) as present, 14 as wanted
from wanted w
join pg_proc p on p.proname = split_part(w.fn, '.', 2)
  and p.pronamespace = split_part(w.fn, '.', 1)::regnamespace
union all
select 'policies', count(*), 53 from pg_policies
  where schemaname in ('public', 'private');

-- Every table the app reads or writes. All 20 must be present.
with wanted(object) as (
  values ('public.profiles'), ('public.organizations'),
         ('public.organization_memberships'), ('public.classes'),
         ('public.students'), ('public.class_enrollments'),
         ('public.skills'), ('public.assessments'),
         ('public.attendance_sessions'), ('public.attendance_records'),
         ('public.leaves'), ('public.contents'), ('public.tasks'),
         ('public.task_submissions'), ('public.announcements'),
         ('public.fee_structures'), ('public.payments'),
         ('public.feedback'), ('public.audit_log'), ('public.invitations')
)
select w.object, (to_regclass(w.object) is not null) as exists
from wanted w
where (to_regclass(w.object) is not null) is not true
union all
select '--- all present ---', true
where not exists (
  select 1 from wanted w where to_regclass(w.object) is null
);

-- The 7 RPCs the Flutter app calls over PostgREST.
with wanted(fn) as (
  values ('create_coach_workspace'), ('deployment_needs_bootstrap'),
         ('invitation_details'), ('create_invitation'),
         ('accept_invitation'), ('unlinked_student_records'),
         ('link_student_record')
)
select w.fn, (p.oid is not null) as exists
from wanted w
left join pg_proc p on p.proname = w.fn
  and p.pronamespace = 'public'::regnamespace
order by p.oid nulls last, w.fn;

-- V9 added this column; invitation acceptance depends on it.
select exists (
  select 1 from information_schema.columns
  where table_schema = 'public' and table_name = 'students'
    and column_name = 'membership_id'
) as students_membership_id_exists;

-- Your data. One organization means the first admin already exists, so the
-- "Create studio" button on the no-workspace screen will be hidden.
select
  (select count(*) from public.organizations) as studios,
  (select count(*) from public.organization_memberships) as memberships,
  (select count(*) from public.invitations) as invitations;

-- Who has access, and who does not. This is the table that matters: a row in
-- public.organization_memberships is what grants access, NOT public.profiles.
-- public.profiles only holds a display name and phone number, and nothing in
-- the app reads it, so a missing profile row is harmless.
select
  u.email,
  coalesce(string_agg(o.name || ' (' || m.role || ')', ', '), 'no studio') as access,
  -- Aggregate, not the raw m.id: m.id is neither grouped nor aggregated here.
  (count(m.id) > 0) as has_access
from auth.users u
left join public.organization_memberships m on m.user_id = u.id
left join public.organizations o on o.id = m.organization_id
group by u.id, u.email
order by has_access desc, u.email;

-- Public.create_coach_workspace / deployment_needs_bootstrap work off
-- organization_memberships, so this is the authoritative "can this person log
-- in to the app" answer.
select public.deployment_needs_bootstrap() as needs_first_admin;