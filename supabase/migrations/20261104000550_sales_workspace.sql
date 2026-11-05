-- ENHAR BUSINESS | Sales workspace, cash registers, invoice settings and promotions
-- Run after migrations 002, 003 and 004.
begin;

create table if not exists public.enhar_sales_screens (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 screen_name text not null,
 is_enabled boolean not null default true,
 settings jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 unique(company_id,id),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id)
);

create table if not exists public.enhar_cash_registers (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 screen_id uuid,
 register_code text not null,
 register_name text not null,
 assigned_user_id uuid references auth.users(id),
 is_enabled boolean not null default true,
 created_at timestamptz not null default now(),
 unique(company_id,id),
 unique(company_id,register_code),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 foreign key(company_id,screen_id) references public.enhar_sales_screens(company_id,id)
);

create table if not exists public.enhar_cash_sessions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 register_id uuid not null,
 branch_id uuid not null,
 opened_by uuid not null default auth.uid() references auth.users(id),
 closed_by uuid references auth.users(id),
 opened_at timestamptz not null default now(),
 closed_at timestamptz,
 opening_amount numeric(14,2) not null default 0 check(opening_amount>=0),
 expected_amount numeric(14,2),
 counted_amount numeric(14,2),
 difference_amount numeric(14,2),
 status text not null default 'OPEN' check(status in ('OPEN','CLOSED')),
 closing_notes text,
 unique(company_id,id),
 foreign key(company_id,register_id) references public.enhar_cash_registers(company_id,id),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 check((status='OPEN' and closed_at is null) or (status='CLOSED' and closed_at is not null))
);
create unique index if not exists enhar_one_open_session_per_register
 on public.enhar_cash_sessions(company_id,register_id) where status='OPEN';

create table if not exists public.enhar_cash_movements (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 session_id uuid not null,
 movement_type text not null check(movement_type in ('SALE','REFUND','CASH_IN','CASH_OUT')),
 payment_method text not null default 'CASH',
 amount numeric(14,2) not null check(amount>0),
 reference text,
 notes text,
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 foreign key(company_id,session_id) references public.enhar_cash_sessions(company_id,id) on delete cascade
);

create table if not exists public.enhar_invoice_settings (
 company_id uuid primary key references public.enhar_companies(id) on delete cascade,
 paper_size text not null default 'A4' check(paper_size in ('A4','THERMAL_80','THERMAL_58')),
 show_logo boolean not null default true,
 show_company_address boolean not null default true,
 show_vat_number boolean not null default true,
 show_cr_number boolean not null default true,
 show_customer_data boolean not null default true,
 show_cashier boolean not null default true,
 show_branch boolean not null default true,
 show_payment_method boolean not null default true,
 show_tax_breakdown boolean not null default true,
 show_qr_code boolean not null default true,
 footer_text text,
 updated_at timestamptz not null default now()
);

create table if not exists public.enhar_sales_promotions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 promotion_name text not null,
 promotion_type text not null check(promotion_type in ('PERCENT','FIXED','BUNDLE_PRICE')),
 applies_to text not null default 'ALL' check(applies_to in ('ALL','PRODUCT','SERVICE','CATEGORY')),
 category_id uuid,
 product_id uuid,
 discount_value numeric(14,2) not null default 0 check(discount_value>=0),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 branch_id uuid,
 usage_limit integer,
 usage_count integer not null default 0,
 is_active boolean not null default true,
 terms text,
 created_at timestamptz not null default now(),
 unique(company_id,id),
 foreign key(company_id,category_id) references public.enhar_item_categories(company_id,id),
 foreign key(company_id,product_id) references public.enhar_products(company_id,id),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 check(ends_at>starts_at)
);

create table if not exists public.enhar_module_controls (
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 module_key text not null,
 is_enabled boolean not null default true,
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default now(),
 primary key(company_id,module_key)
);

create table if not exists public.enhar_role_permissions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 role_key text not null,
 module_key text not null,
 can_view boolean not null default false,
 can_create boolean not null default false,
 can_update boolean not null default false,
 can_delete boolean not null default false,
 can_manage_settings boolean not null default false,
 unique(company_id,role_key,module_key)
);

do $$
declare t text;
begin
 foreach t in array array['enhar_sales_screens','enhar_cash_registers','enhar_cash_sessions','enhar_cash_movements','enhar_invoice_settings','enhar_sales_promotions','enhar_module_controls','enhar_role_permissions'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists %I on public.%I',t||'_member_access',t);
  execute format('create policy %I on public.%I for all to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin()) with check (public.enhar_is_company_member(company_id) or public.is_platform_admin())',t||'_member_access',t);
  execute format('revoke all on public.%I from anon',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 end loop;
end $$;

create index if not exists enhar_cash_sessions_company_branch_date_idx on public.enhar_cash_sessions(company_id,branch_id,opened_at desc);
create index if not exists enhar_cash_movements_session_idx on public.enhar_cash_movements(company_id,session_id,created_at);
create index if not exists enhar_promotions_period_idx on public.enhar_sales_promotions(company_id,starts_at,ends_at,is_active);

commit;
