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
| 1 | Sign up / registration | In Progress | High | Next step - password hashing, user table |
| 2 | Add & manage students | Coming Soon | High | Schema exists, UI placeholder |
| 3 | Attendance marking | Coming Soon | High | Schema exists, UI placeholder |
| 4 | Approve student leaves | Coming Soon | High | V2 schema done, UI needed |
| 5 | Content management & upload | Coming Soon | Medium | V3 schema done, UI needed |
| 6 | Assign tasks/demos | Coming Soon | Medium | V4 schema done, UI needed |
| 7 | Performance reports | Coming Soon | Medium | Assessments schema exists |
| 8 | Publish announcements | Coming Soon | Medium | V5 schema done, UI needed |
| 9 | Fee structure management | Coming Soon | Low | V6 schema done, UI needed |
| 10 | Payment tracking | Coming Soon | Low | V6 schema done, UI needed |

### Student (Front Office)

| # | Feature | Status | Priority | Notes |
|---|---|---|---|---|
| 1 | Log in | Done | High | Email + phone OTP |
| 2 | Student dashboard | Coming Soon | High | Placeholder |
| 3 | Apply attendance | Coming Soon | High | Not built |
| 4 | Apply leaves | Coming Soon | High | V2 schema done, UI needed |
| 5 | Fee details & payments | Coming Soon | Medium | V6 schema done, UI needed |
| 6 | Access content & tasks | Coming Soon | Medium | V3/V4 schema done |
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
| 3 | Sign up / registration | In Progress | High | Password hashing, user table |
| 4 | Role-based page access | Coming Soon | High | Admin vs student routing |
| 5 | Password reset | Coming Soon | Medium | Not built |

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

## Next Step: Admin Registration Portal

| Task | Status |
|---|---|
| Create registration page UI | Pending |
| Password hashing (bcrypt/argon2) | Pending |
| User table with roles | Pending |
| Form validation | Pending |
| Error handling | Pending |
| Redirect to login after registration | Pending |

---

## Status Legend

| Marker | Meaning |
|---|---|
| Done | Working and tested |
| In Progress | Currently being built |
| Coming Soon | Not started, planned |
| Pending | Waiting on dependency |
