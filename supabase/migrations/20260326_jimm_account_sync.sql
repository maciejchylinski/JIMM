-- JIMM cloud backup / sync schema + RLS
-- Run in Supabase SQL Editor (or via supabase db push).
-- Uses only authenticated user JWT + anon key from the app.
-- Never grant table privileges to anon beyond RLS-filtered auth.uid() policies.

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- User-saved custom exercises (built-in catalog is NOT synced)
-- ---------------------------------------------------------------------------
create table if not exists public.exercises (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  category text not null default '',
  search_metadata text not null default '',
  source text not null default 'user_saved',
  is_hidden_from_library boolean,
  logging_type text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint exercises_source_check check (source in ('user_saved'))
);

create index if not exists exercises_user_id_idx on public.exercises (user_id);
create index if not exists exercises_user_updated_idx on public.exercises (user_id, updated_at);

-- ---------------------------------------------------------------------------
-- Workout sessions
-- ---------------------------------------------------------------------------
create table if not exists public.workout_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text,
  session_date timestamptz not null,
  started_from_plan_template boolean,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists workout_sessions_user_id_idx on public.workout_sessions (user_id);
create index if not exists workout_sessions_user_updated_idx on public.workout_sessions (user_id, updated_at);

-- ---------------------------------------------------------------------------
-- Workout session exercises
-- ---------------------------------------------------------------------------
create table if not exists public.workout_session_exercises (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  session_id uuid not null references public.workout_sessions (id) on delete cascade,
  exercise_order int not null default 1,
  exercise_id uuid references public.exercises (id) on delete set null,
  built_in_exercise_name text,
  source text not null default 'built_in',
  custom_exercise_name text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint workout_session_exercises_source_check
    check (source in ('built_in', 'user_saved', 'session_only'))
);

create index if not exists workout_session_exercises_user_id_idx
  on public.workout_session_exercises (user_id);
create index if not exists workout_session_exercises_session_id_idx
  on public.workout_session_exercises (session_id);

-- ---------------------------------------------------------------------------
-- Workout sets
-- ---------------------------------------------------------------------------
create table if not exists public.workout_sets (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  session_exercise_id uuid not null references public.workout_session_exercises (id) on delete cascade,
  set_order int not null default 1,
  weight double precision not null default 0,
  reps int not null default 0,
  is_pending_suggestion boolean not null default false,
  rest_duration_seconds int,
  duration_seconds int,
  distance_meters double precision,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists workout_sets_user_id_idx on public.workout_sets (user_id);
create index if not exists workout_sets_session_exercise_id_idx
  on public.workout_sets (session_exercise_id);

-- ---------------------------------------------------------------------------
-- Workout plans / templates
-- ---------------------------------------------------------------------------
create table if not exists public.workout_plans (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists workout_plans_user_id_idx on public.workout_plans (user_id);

create table if not exists public.workout_plan_exercises (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid not null references public.workout_plans (id) on delete cascade,
  exercise_order int not null default 1,
  exercise_id uuid references public.exercises (id) on delete set null,
  built_in_exercise_name text,
  custom_exercise_name text,
  source text not null default 'built_in',
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint workout_plan_exercises_source_check
    check (source in ('built_in', 'user_saved', 'session_only'))
);

create index if not exists workout_plan_exercises_user_id_idx
  on public.workout_plan_exercises (user_id);
create index if not exists workout_plan_exercises_plan_id_idx
  on public.workout_plan_exercises (plan_id);

-- ---------------------------------------------------------------------------
-- Sync metadata (per-device / per-user last sync cursor)
-- ---------------------------------------------------------------------------
create table if not exists public.sync_metadata (
  user_id uuid primary key references auth.users (id) on delete cascade,
  last_synced_at timestamptz,
  client_device_id text,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Auto-create profile on signup
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, created_at, updated_at)
  values (new.id, new.email, now(), now())
  on conflict (id) do update
    set email = excluded.email,
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------------------------
-- updated_at helper
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.exercises enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.workout_session_exercises enable row level security;
alter table public.workout_sets enable row level security;
alter table public.workout_plans enable row level security;
alter table public.workout_plan_exercises enable row level security;
alter table public.sync_metadata enable row level security;

-- Revoke any broad grants; authenticated users access only via RLS.
revoke all on public.profiles from anon, authenticated;
revoke all on public.exercises from anon, authenticated;
revoke all on public.workout_sessions from anon, authenticated;
revoke all on public.workout_session_exercises from anon, authenticated;
revoke all on public.workout_sets from anon, authenticated;
revoke all on public.workout_plans from anon, authenticated;
revoke all on public.workout_plan_exercises from anon, authenticated;
revoke all on public.sync_metadata from anon, authenticated;

grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.exercises to authenticated;
grant select, insert, update, delete on public.workout_sessions to authenticated;
grant select, insert, update, delete on public.workout_session_exercises to authenticated;
grant select, insert, update, delete on public.workout_sets to authenticated;
grant select, insert, update, delete on public.workout_plans to authenticated;
grant select, insert, update, delete on public.workout_plan_exercises to authenticated;
grant select, insert, update, delete on public.sync_metadata to authenticated;

-- Profiles
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated
  using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated
  with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own" on public.profiles
  for delete to authenticated
  using (auth.uid() = id);

-- Generic owner policies for user_id tables
-- exercises
drop policy if exists "exercises_select_own" on public.exercises;
create policy "exercises_select_own" on public.exercises
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "exercises_insert_own" on public.exercises;
create policy "exercises_insert_own" on public.exercises
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "exercises_update_own" on public.exercises;
create policy "exercises_update_own" on public.exercises
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "exercises_delete_own" on public.exercises;
create policy "exercises_delete_own" on public.exercises
  for delete to authenticated using (auth.uid() = user_id);

-- workout_sessions
drop policy if exists "workout_sessions_select_own" on public.workout_sessions;
create policy "workout_sessions_select_own" on public.workout_sessions
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "workout_sessions_insert_own" on public.workout_sessions;
create policy "workout_sessions_insert_own" on public.workout_sessions
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "workout_sessions_update_own" on public.workout_sessions;
create policy "workout_sessions_update_own" on public.workout_sessions
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "workout_sessions_delete_own" on public.workout_sessions;
create policy "workout_sessions_delete_own" on public.workout_sessions
  for delete to authenticated using (auth.uid() = user_id);

-- workout_session_exercises
drop policy if exists "workout_session_exercises_select_own" on public.workout_session_exercises;
create policy "workout_session_exercises_select_own" on public.workout_session_exercises
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "workout_session_exercises_insert_own" on public.workout_session_exercises;
create policy "workout_session_exercises_insert_own" on public.workout_session_exercises
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "workout_session_exercises_update_own" on public.workout_session_exercises;
create policy "workout_session_exercises_update_own" on public.workout_session_exercises
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "workout_session_exercises_delete_own" on public.workout_session_exercises;
create policy "workout_session_exercises_delete_own" on public.workout_session_exercises
  for delete to authenticated using (auth.uid() = user_id);

-- workout_sets
drop policy if exists "workout_sets_select_own" on public.workout_sets;
create policy "workout_sets_select_own" on public.workout_sets
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "workout_sets_insert_own" on public.workout_sets;
create policy "workout_sets_insert_own" on public.workout_sets
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "workout_sets_update_own" on public.workout_sets;
create policy "workout_sets_update_own" on public.workout_sets
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "workout_sets_delete_own" on public.workout_sets;
create policy "workout_sets_delete_own" on public.workout_sets
  for delete to authenticated using (auth.uid() = user_id);

-- workout_plans
drop policy if exists "workout_plans_select_own" on public.workout_plans;
create policy "workout_plans_select_own" on public.workout_plans
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "workout_plans_insert_own" on public.workout_plans;
create policy "workout_plans_insert_own" on public.workout_plans
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "workout_plans_update_own" on public.workout_plans;
create policy "workout_plans_update_own" on public.workout_plans
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "workout_plans_delete_own" on public.workout_plans;
create policy "workout_plans_delete_own" on public.workout_plans
  for delete to authenticated using (auth.uid() = user_id);

-- workout_plan_exercises
drop policy if exists "workout_plan_exercises_select_own" on public.workout_plan_exercises;
create policy "workout_plan_exercises_select_own" on public.workout_plan_exercises
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "workout_plan_exercises_insert_own" on public.workout_plan_exercises;
create policy "workout_plan_exercises_insert_own" on public.workout_plan_exercises
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "workout_plan_exercises_update_own" on public.workout_plan_exercises;
create policy "workout_plan_exercises_update_own" on public.workout_plan_exercises
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "workout_plan_exercises_delete_own" on public.workout_plan_exercises;
create policy "workout_plan_exercises_delete_own" on public.workout_plan_exercises
  for delete to authenticated using (auth.uid() = user_id);

-- sync_metadata
drop policy if exists "sync_metadata_select_own" on public.sync_metadata;
create policy "sync_metadata_select_own" on public.sync_metadata
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "sync_metadata_insert_own" on public.sync_metadata;
create policy "sync_metadata_insert_own" on public.sync_metadata
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "sync_metadata_update_own" on public.sync_metadata;
create policy "sync_metadata_update_own" on public.sync_metadata
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "sync_metadata_delete_own" on public.sync_metadata;
create policy "sync_metadata_delete_own" on public.sync_metadata
  for delete to authenticated using (auth.uid() = user_id);
