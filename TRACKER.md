# Strivo - Project Tracker

## Project Overview

| Item | Details |
|---|---|
| **Project** | Strivo - Education Management System |
| **Tech Stack** | Flutter + Riverpod + go_router + Supabase |
| **Backend** | Supabase (PostgreSQL, Auth, RLS, Storage) |
| **Containerization** | Docker + nginx |
| **Repo** | github.com/yogeshwaranyogi2806-hue/Strivo |

---

## Feature Tracker

### Admin (Back Office)

| # | Feature | Status | Priority | Notes |
|---|---|---|---|---|
| 1 | Sign up / registration | Done | High | Invite-driven, see Registration Model |
| 2 | Add & manage students | Coming Soon | High | Schema exists, UI placeholder |
| 3 | Attendance marking | Coming Soon | High | Schema exists, UI placeholder |
| 4 | Approve student leaves | Coming Soon | High | V2 schema done, coach UI needed |
| 5 | Content management & upload | Partial | Medium | Create/publish/delete done. File *upload* not built; accepts a link |
| 6 | Assign tasks/demos | Coming Soon | Medium | V4 schema done, UI needed |
| 7 | Performance reports | Coming Soon | Medium | Assessments schema exists |
| 8 | Publish announcements | Coming Soon | Medium | V5 schema done, UI needed |
| 9 | Fee structure management | Coming Soon | Low | V6 schema done, UI needed |
| 10 | Payment tracking | Coming Soon | Low | V6 schema done, UI needed |

### Student Records

The student record is what attendance, fees and history attach to. A student
record created by a coach has no login attached, so that student can sign in
but sees nothing. Two mechanisms close the gap:

1. **Automatic.** When an invite is redeemed, `accept_invitation` looks for an
   unlinked student record in that studio with the same name and links it
   instead of creating a duplicate. Only applied when the match is unambiguous.
2. **By hand.** More → *Student records* lists both sides of every mismatch and
   lets a coach pair them. Backed by V11.

Duplicating a student record splits their attendance and fees across two rows,
which is why the automatic path links rather than inserts.

### Student (Front Office)

| # | Feature | Status | Priority | Notes |
|---|---|---|---|---|
| 1 | Log in | Done | High | Email + phone OTP |
| 2 | Student dashboard | Done | High | Home, tasks, leave, fees, attendance, profile |
| 3 | Apply attendance | Coming Soon | High | Needs V10 policies applied; coach side not built |
| 4 | Apply leaves | Done | High | Apply + review status visible to the student |
| 5 | Fee details & payments | Done | Medium | Outstanding total, history, studio fee list |
| 6 | Access content & tasks | Done | Medium | Tasks, submissions, and the published content library |
| 7 | Performance reports (downloadable) | Coming Soon | Medium | Not built |
| 8 | Feedback submission | Coming Soon | Low | V7 schema done, UI needed |

### Public (No Auth)

| # | Feature | Status | Priority | Notes |
|---|---|---|---|---|
| 1 | Welcome / landing page | Coming Soon | High | Not built |
| 2 | Coaches/teachers showcase | Coming Soon | Medium | Not built |
| 3 | Content details | Coming Soon | Medium | Not built |
| 4 | Achievements display | Coming Soon | Low | Not built |
| 5 | Announcements feed | Coming Soon | Medium | Not built |
| 6 | Fee structure display | Coming Soon | Low | Not built |
| 7 | Course details | Coming Soon | Medium | Not built |

### Authentication

| # | Feature | Status | Priority | Notes |
|---|---|---|---|---|
| 1 | Email/password login | Done | High | Working |
| 2 | Phone OTP login | Done | High | Working |
| 1 | Sign up / registration | Done | High | Invite-driven. 2-step: code check, then account + membership |
| 4 | Role-based page access | Done | High | Admins and students land on separate, separately gated apps |
| 5 | Password reset | Coming Soon | Medium | Not built |
| 6 | OTP sign up | Coming Soon | Medium | Phone OTP login exists; OTP *registration* deferred |

---

## Database Migrations

| Version | File | Description | Status |
|---|---|---|---|
| V1 | `V1__initial_coach_schema.sql` | Core schema (profiles, orgs, classes, students, skills, assessments, attendance) | Applied |
| V2 | `V2__add_leaves.sql` | Leave applications with approval workflow | Applied |
| V3 | `V3__add_contents.sql` | Content management and uploads | Applied |
| V4 | `V4__add_tasks.sql` | Tasks, demos, and submissions | Applied |
| V5 | `V5__add_announcements.sql` | Admin-published announcements | Applied |
| V6 | `V6__add_fees_payments.sql` | Fee structures and payment records | Applied |
| V7 | `V7__add_feedback.sql` | Student feedback and suggestions | Applied |
| V8 | `V8__add_audit_log.sql` | Audit trail of actions, written via a non-forgeable RPC | Pending |
| V9 | `V9__add_invitations.sql` | Invite codes: create / preview / accept. Also adds `students.membership_id` | Pending |
| V10 | `V10__allow_students_to_read_own_records.sql` | Self-scoped read policies for students: own record, attendance, enrollments, classes | Pending |
| V11 | `V11__link_student_records.sql` | `unlinked_student_records()` and `link_student_record()` so a coach can match a login to a student record | Pending |

### Registration Model

Nobody self-registers. An existing admin generates a single-use invite, sends it,
and the recipient enters the code and fills in their own details.

| Flow | Role | Result |
|---|---|---|
| Admin invites admin | `owner` / `coach` | Membership in the same studio |
| Admin invites student | `student` | Membership **plus** a `students` row |

An invite can optionally be locked to one email address, in which case only that
mailbox can redeem it.

**Bootstrap:** the first admin cannot be invited, because inviting requires an
admin. Add one user in the Supabase dashboard, then run
`select public.create_coach_workspace('Studio Name');`. Every account after that
is invited.

**Known gap:** invites are shared as a code, not a deep link. Sending
`strivo://invite/<code>` and opening the app straight on it needs App Links in
`AndroidManifest.xml` plus an intent-filter package. The signup page already
accepts a pasted link, so only the tap-to-open half is missing.

---

---

## Infrastructure

| Item | Status | Notes |
|---|---|---|
| Git repository | Done | Pushed to GitHub |
| Docker setup | Done | Dockerfile, docker-compose, nginx |
| Migration system | Done | Flyway-style V1-V7 |
| .env configuration | Done | Supabase credentials |
| Code segregation | Done | back_office, front_office, public, shared |
| Browser prototype | Done | Design reference only |

---

## Observability

| Item | Status | Notes |
|---|---|---|
| Structured logger (`AppLog`) | Done | JSON-per-line, 200-entry ring buffer, never throws |
| Daily rotating log file | Done | Android/iOS, app-private storage, 7-day retention |
| Global error capture | Done | `FlutterError.onError`, `PlatformDispatcher.onError`, error zone, 2s de-dupe |
| In-app log viewer | Done | More tab → Activity log. Filter, copy, open files |
| Audit service | Done | Local file first, DB sync best-effort |
| `audit_log` table + RPC | Done | Needs V8 applied |
| Web fallback | Done | Conditional import; console only, web build unaffected |
| Prototype log + export | Done | `app.js` console log, "Export log" downloads the day |
| Audit hooks for features | Partial | Only the 3 flows that exist today are wired |
| Remote sink (Sentry etc.) | Coming Soon | Not needed before pilot |

Action event vocabulary so far: `auth.login_succeeded`, `auth.login_failed`,
`auth.otp_requested`, `workspace.created`, `workspace.create_failed`.

---

## Next Step: Coach Workflows

Registration and role routing are done. Both dashboards exist and are gated by
the caller's membership role.

| Area | Status |
|---|---|
| Invite-driven registration | Done |
| Role routing (back office vs front office) | Done |
| Student dashboard (tasks, leave, fees, attendance, profile) | Done |
| Coach back office (classes, rosters, attendance marking, grading) | Next |

### Why a signed-in user with no studio gets a dead end

`/no-workspace` intentionally offers no way to create a workspace. It is the
state a brand-new auth user lands in before an admin invites them, and the
first admin is bootstrapped by hand. Letting anyone with a login spin up their
own studio would reopen the self-registration hole that invitations exist to
close.

### Two schema gaps found while building the student side

1. **`students` had no link to the auth login.** V9 adds
   `students.membership_id`. Without it there is no way to tell whose student
   row it is, so leave requests, task submissions and payments all have nothing
   to attach to.
2. **Every policy on a student's own data was coach-only.** A student could not
   read their own student row or their attendance. V10 adds self-scoped read
   policies and nothing else -- no new write access.

### Apply order

V10 depends on `students.membership_id` from V9, and V11 depends on the V9
column too. Apply V8, V9, V10, V11 in order, or use `supabase/apply_all.sql`
which has them concatenated.

---

## Status Legend

| Marker | Meaning |
|---|---|
| Done | Working and tested |
| In Progress | Currently being built |
| Coming Soon | Not started, planned |
| Pending | Waiting on dependency |
