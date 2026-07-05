create extension if not exists pgcrypto;

create table if not exists public.licenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  license_key text not null unique,
  plan text not null default 'pro',
  status text not null default 'active',
  max_devices integer not null default 1,
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.license_activations (
  id uuid primary key default gen_random_uuid(),
  license_id uuid not null references public.licenses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  device_name text,
  last_seen_at timestamptz not null default timezone('utc', now()),
  activated_at timestamptz not null default timezone('utc', now()),
  metadata jsonb not null default '{}'::jsonb,
  unique (license_id, device_id)
);

create index if not exists licenses_user_id_idx on public.licenses (user_id);
create index if not exists license_activations_user_id_idx on public.license_activations (user_id);
create index if not exists license_activations_license_id_idx on public.license_activations (license_id);

alter table public.licenses enable row level security;
alter table public.license_activations enable row level security;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists licenses_set_updated_at on public.licenses;
create trigger licenses_set_updated_at
before update on public.licenses
for each row
execute function public.set_updated_at();

drop policy if exists "users_select_own_licenses" on public.licenses;
create policy "users_select_own_licenses"
on public.licenses
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "users_select_own_activations" on public.license_activations;
create policy "users_select_own_activations"
on public.license_activations
for select
to authenticated
using (auth.uid() = user_id);
