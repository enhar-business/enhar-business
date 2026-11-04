-- ENHAR BUSINESS | Supabase tenant foundation
-- Migration 002: secure company, membership, branch and warehouse foundation.
-- Run in Supabase SQL Editor as the project owner. Safe to re-run.
-- This migration does NOT expose secret keys and does NOT enable direct client writes
-- to company membership or platform administration tables.

begin;

create extension if not exists pgcrypto;

-- Platform administrator check. The underlying platform.platform_admins table
-- was bootstrapped separately; only the signed-in user's own auth.uid() is checked.
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from platform.platform_admins pa
    where pa.user_id = (select auth.uid())
      and pa.admin_role = 'SUPER_ADMIN'
  );
$function$;

revoke all on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

create table if not exists public.enhar_companies (
  id uuid primary key default gen_random_uuid(),
  company_code text not null unique,
  name_ar text not null check (char_length(trim(name_ar)) between 2 and 200),
  name_en text,
  commercial_registration text,
  vat_number text,
  base_currency char(3) not null default 'SAR',
  timezone text not null default 'Asia/Riyadh',
  default_language text not null default 'ar' check (default_language in ('ar','en')),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','SUSPENDED','CLOSED')),
  subscription_status text not null default 'TRIAL' check (subscription_status in ('TRIAL','ACTIVE','PAST_DUE','SUSPENDED','CANCELLED')),
  trial_started_at timestamptz not null default now(),
  trial_ends_at timestamptz not null default (now() + interval '15 days'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.enhar_company_memberships (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('OWNER','ADMIN','MANAGER','ACCOUNTANT','SALES','WAREHOUSE','VIEWER')),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INVITED','SUSPENDED')),
  created_at timestamptz not null default now(),
  unique(company_id, user_id)
);

create table if not exists public.enhar_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  preferred_language text not null default 'ar' check (preferred_language in ('ar','en')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.enhar_branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  branch_code text not null,
  name_ar text not null,
  name_en text,
  address jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(company_id, branch_code),
  unique(company_id, id)
);

create table if not exists public.enhar_warehouses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  branch_id uuid not null,
  warehouse_code text not null,
  name_ar text not null,
  name_en text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(company_id, warehouse_code),
  foreign key(company_id, branch_id)
    references public.enhar_branches(company_id, id) on delete restrict
);

create index if not exists enhar_memberships_user_idx
  on public.enhar_company_memberships(user_id, status);
create index if not exists enhar_branches_company_idx
  on public.enhar_branches(company_id);
create index if not exists enhar_warehouses_company_idx
  on public.enhar_warehouses(company_id, branch_id);

-- SECURITY DEFINER membership predicates avoid recursive RLS policy evaluation.
create or replace function public.enhar_is_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.enhar_company_memberships m
    where m.company_id = p_company_id
      and m.user_id = (select auth.uid())
      and m.status = 'ACTIVE'
  );
$function$;

create or replace function public.enhar_is_company_admin(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.enhar_company_memberships m
    where m.company_id = p_company_id
      and m.user_id = (select auth.uid())
      and m.status = 'ACTIVE'
      and m.role in ('OWNER','ADMIN')
  );
$function$;

revoke all on function public.enhar_is_company_member(uuid) from public, anon;
revoke all on function public.enhar_is_company_admin(uuid) from public, anon;
grant execute on function public.enhar_is_company_member(uuid) to authenticated;
grant execute on function public.enhar_is_company_admin(uuid) to authenticated;

alter table public.enhar_companies enable row level security;
alter table public.enhar_company_memberships enable row level security;
alter table public.enhar_profiles enable row level security;
alter table public.enhar_branches enable row level security;
alter table public.enhar_warehouses enable row level security;

drop policy if exists enhar_companies_read_member on public.enhar_companies;
create policy enhar_companies_read_member on public.enhar_companies
for select to authenticated
using (public.enhar_is_company_member(id) or public.is_platform_admin());

drop policy if exists enhar_companies_update_admin on public.enhar_companies;
create policy enhar_companies_update_admin on public.enhar_companies
for update to authenticated
using (public.enhar_is_company_admin(id) or public.is_platform_admin())
with check (public.enhar_is_company_admin(id) or public.is_platform_admin());

drop policy if exists enhar_memberships_read_member on public.enhar_company_memberships;
create policy enhar_memberships_read_member on public.enhar_company_memberships
for select to authenticated
using (user_id = (select auth.uid())
  or public.enhar_is_company_admin(company_id)
  or public.is_platform_admin());

drop policy if exists enhar_profiles_read_self on public.enhar_profiles;
create policy enhar_profiles_read_self on public.enhar_profiles
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists enhar_profiles_insert_self on public.enhar_profiles;
create policy enhar_profiles_insert_self on public.enhar_profiles
for insert to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists enhar_profiles_update_self on public.enhar_profiles;
create policy enhar_profiles_update_self on public.enhar_profiles
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists enhar_branches_read_member on public.enhar_branches;
create policy enhar_branches_read_member on public.enhar_branches
for select to authenticated
using (public.enhar_is_company_member(company_id) or public.is_platform_admin());

drop policy if exists enhar_branches_write_admin on public.enhar_branches;
create policy enhar_branches_write_admin on public.enhar_branches
for all to authenticated
using (public.enhar_is_company_admin(company_id) or public.is_platform_admin())
with check (public.enhar_is_company_admin(company_id) or public.is_platform_admin());

drop policy if exists enhar_warehouses_read_member on public.enhar_warehouses;
create policy enhar_warehouses_read_member on public.enhar_warehouses
for select to authenticated
using (public.enhar_is_company_member(company_id) or public.is_platform_admin());

drop policy if exists enhar_warehouses_write_admin on public.enhar_warehouses;
create policy enhar_warehouses_write_admin on public.enhar_warehouses
for all to authenticated
using (public.enhar_is_company_admin(company_id) or public.is_platform_admin())
with check (public.enhar_is_company_admin(company_id) or public.is_platform_admin());

-- Explicit table privileges: RLS remains the row-level enforcement boundary.
revoke all on public.enhar_companies, public.enhar_company_memberships,
  public.enhar_profiles, public.enhar_branches, public.enhar_warehouses from anon, authenticated;
grant select on public.enhar_companies to authenticated; -- subscription/status changes are server-admin only
grant select on public.enhar_company_memberships to authenticated;
grant select, insert, update on public.enhar_profiles to authenticated;
grant select, insert, update, delete on public.enhar_branches, public.enhar_warehouses to authenticated;

-- A signed-in user can create a company and become its OWNER.
-- Company creation, owner membership, default branch and warehouse are atomic.
create or replace function public.enhar_create_company_for_current_user(
  p_name_ar text,
  p_name_en text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_branch_id uuid;
  v_company_code text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_name_ar is null or char_length(trim(p_name_ar)) < 2
     or char_length(trim(p_name_ar)) > 200 then
    raise exception 'Company Arabic name must be between 2 and 200 characters';
  end if;

  v_company_code := 'ENH-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

  insert into public.enhar_companies
    (company_code, name_ar, name_en, created_by, trial_started_at, trial_ends_at)
  values
    (v_company_code, trim(p_name_ar), nullif(trim(coalesce(p_name_en,'')), ''),
     v_user_id, now(), now() + interval '15 days')
  returning id into v_company_id;

  insert into public.enhar_company_memberships(company_id, user_id, role, status)
  values (v_company_id, v_user_id, 'OWNER', 'ACTIVE');

  insert into public.enhar_branches(company_id, branch_code, name_ar, name_en)
  values (v_company_id, 'MAIN', 'الفرع الرئيسي', 'Main Branch')
  returning id into v_branch_id;

  insert into public.enhar_warehouses(company_id, branch_id, warehouse_code, name_ar, name_en)
  values (v_company_id, v_branch_id, 'MAIN', 'المستودع الرئيسي', 'Main Warehouse');

  return jsonb_build_object(
    'company_id', v_company_id,
    'company_code', v_company_code,
    'trial_days', 15,
    'trial_ends_at', (select c.trial_ends_at from public.enhar_companies c where c.id = v_company_id)
  );
end;
$function$;

revoke all on function public.enhar_create_company_for_current_user(text, text) from public, anon;
grant execute on function public.enhar_create_company_for_current_user(text, text) to authenticated;

commit;

-- After running, verify with:
-- select table_name from information_schema.tables
-- where table_schema='public' and table_name like 'enhar_%' order by table_name;
