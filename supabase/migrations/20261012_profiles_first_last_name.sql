-- Add first/last name on profiles (owner-only via existing RLS).
-- Safe to re-run.

alter table public.profiles
  add column if not exists first_name text;

alter table public.profiles
  add column if not exists last_name text;

-- Copy signup metadata into profiles when a user is created.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta_first text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'first_name', '')), '');
  meta_last text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'last_name', '')), '');
  meta_display text := nullif(
    trim(both from concat_ws(' ', meta_first, meta_last)),
    ''
  );
begin
  insert into public.profiles (id, email, first_name, last_name, display_name, created_at, updated_at)
  values (new.id, new.email, meta_first, meta_last, meta_display, now(), now())
  on conflict (id) do update
    set email = excluded.email,
        first_name = coalesce(excluded.first_name, public.profiles.first_name),
        last_name = coalesce(excluded.last_name, public.profiles.last_name),
        display_name = coalesce(excluded.display_name, public.profiles.display_name),
        updated_at = now();
  return new;
end;
$$;
