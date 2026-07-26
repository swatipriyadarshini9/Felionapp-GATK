-- Felino Genomics: profiles, analyses, variants + RLS
-- Run in Supabase SQL Editor (Dashboard → SQL → New query)

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  otp_verified_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.analyses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  upload_id text not null,
  drug_name text,
  ai_summary text,
  status text not null default 'completed',
  created_at timestamptz not null default now()
);

create table if not exists public.variants (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references public.analyses (id) on delete cascade,
  chromosome text,
  position bigint,
  variant_id text,
  genotype text,
  qual double precision
);

create index if not exists analyses_user_id_idx on public.analyses (user_id);
create index if not exists variants_analysis_id_idx on public.variants (analysis_id);

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
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.analyses enable row level security;
alter table public.variants enable row level security;

-- Profiles: users can read/update their own row
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

-- Analyses: full CRUD limited to owner
drop policy if exists "analyses_select_own" on public.analyses;
create policy "analyses_select_own"
  on public.analyses for select
  using (auth.uid() = user_id);

drop policy if exists "analyses_insert_own" on public.analyses;
create policy "analyses_insert_own"
  on public.analyses for insert
  with check (auth.uid() = user_id);

drop policy if exists "analyses_update_own" on public.analyses;
create policy "analyses_update_own"
  on public.analyses for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "analyses_delete_own" on public.analyses;
create policy "analyses_delete_own"
  on public.analyses for delete
  using (auth.uid() = user_id);

-- Variants: access only via owned parent analysis
drop policy if exists "variants_select_own" on public.variants;
create policy "variants_select_own"
  on public.variants for select
  using (
    exists (
      select 1 from public.analyses a
      where a.id = variants.analysis_id and a.user_id = auth.uid()
    )
  );

drop policy if exists "variants_insert_own" on public.variants;
create policy "variants_insert_own"
  on public.variants for insert
  with check (
    exists (
      select 1 from public.analyses a
      where a.id = variants.analysis_id and a.user_id = auth.uid()
    )
  );

drop policy if exists "variants_update_own" on public.variants;
create policy "variants_update_own"
  on public.variants for update
  using (
    exists (
      select 1 from public.analyses a
      where a.id = variants.analysis_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.analyses a
      where a.id = variants.analysis_id and a.user_id = auth.uid()
    )
  );

drop policy if exists "variants_delete_own" on public.variants;
create policy "variants_delete_own"
  on public.variants for delete
  using (
    exists (
      select 1 from public.analyses a
      where a.id = variants.analysis_id and a.user_id = auth.uid()
    )
  );
