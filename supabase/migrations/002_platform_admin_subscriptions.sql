-- ANHAR migration 002: platform administration and subscription foundation
-- Apply only after migration 001. Do not expose platform-admin access to browser clients.
begin;

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete restrict,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id),
  note text
);
alter table public.platform_admins enable row level security;
-- Intentionally no authenticated policies: only trusted server-side service-role
-- functions and the database owner can inspect or manage platform administrators.
revoke all on public.platform_admins from anon, authenticated;

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  plan_code text not null unique,
  name text not null,
  six_month_price numeric(12,2) not null check (six_month_price >= 0),
  annual_price numeric(12,2) not null check (annual_price >= 0),
  included_cash_drawers integer not null check (included_cash_drawers >= 0),
  included_users integer not null check (included_users >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.subscription_plans enable row level security;
revoke all on public.subscription_plans from anon, authenticated;
create policy subscription_plans_read_authenticated
  on public.subscription_plans for select to authenticated using (is_active);

insert into public.subscription_plans
  (plan_code,name,six_month_price,annual_price,included_cash_drawers,included_users)
values
  ('basic','Basic',1000,1800,2,9),
  ('medium','Medium',1500,2800,4,18),
  ('premium','Premium',2000,3800,6,27)
on conflict (plan_code) do update set
  name=excluded.name,
  six_month_price=excluded.six_month_price,
  annual_price=excluded.annual_price,
  included_cash_drawers=excluded.included_cash_drawers,
  included_users=excluded.included_users;

create table if not exists public.subscription_addon_catalog (
  addon_code text primary key,
  name text not null,
  unit_price numeric(12,2) not null check (unit_price >= 0),
  billing_basis text not null check (billing_basis in ('one_time','per_term')),
  is_active boolean not null default true
);
alter table public.subscription_addon_catalog enable row level security;
revoke all on public.subscription_addon_catalog from anon, authenticated;
create policy subscription_addon_catalog_read_authenticated
  on public.subscription_addon_catalog for select to authenticated using (is_active);

insert into public.subscription_addon_catalog(addon_code,name,unit_price,billing_basis)
values
  ('extra_cash_drawer','Additional cash drawer',300,'per_term'),
  ('extra_user','Additional user',99,'per_term')
on conflict (addon_code) do update set
  name=excluded.name, unit_price=excluded.unit_price,
  billing_basis=excluded.billing_basis, is_active=true;

create table if not exists public.company_subscriptions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  plan_id uuid not null references public.subscription_plans(id) on delete restrict,
  term_months smallint not null check (term_months in (6,12)),
  status text not null default 'trial'
    check (status in ('trial','active','expired','suspended','cancelled')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  trial_ends_at timestamptz,
  extra_cash_drawers integer not null default 0 check (extra_cash_drawers >= 0),
  extra_users integer not null default 0 check (extra_users >= 0),
  price_snapshot numeric(12,2) not null default 0 check (price_snapshot >= 0),
  currency_code char(3) not null default 'SAR',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id,company_id)
);
create unique index if not exists one_current_subscription_per_company
  on public.company_subscriptions(company_id)
  where status in ('trial','active','suspended');
create index if not exists company_subscriptions_status_end_idx
  on public.company_subscriptions(status,ends_at);

alter table public.company_subscriptions enable row level security;
revoke all on public.company_subscriptions from anon, authenticated;
create policy company_subscriptions_member_read
  on public.company_subscriptions for select to authenticated
  using (public.is_company_member(company_id));
-- No client-side INSERT/UPDATE/DELETE policies. Trusted server-side platform
-- functions will perform subscription administration after checking platform_admins.

commit;
