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