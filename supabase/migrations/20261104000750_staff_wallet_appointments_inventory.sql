-- ENHAR BUSINESS | Staff, customer wallet, appointments, POS preferences and stock controls
-- Migration 007. Additive only: preserves existing business records.
begin;

-- Staff directory and user-to-role assignments.
create table if not exists public.enhar_staff (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 user_id uuid references auth.users(id) on delete set null,
 employee_code text not null,
 full_name text not null,
 phone text,
 email text,
 job_title text,
 staff_type text not null default 'SERVICE_PROVIDER'
   check (staff_type in ('SERVICE_PROVIDER','CASHIER','ACCOUNTANT','ACCOUNTS_MANAGER','STOREKEEPER','BRANCH_MANAGER','ADMIN')),
 branch_id uuid,
 can_perform_services boolean not null default false,
 can_be_cashier boolean not null default false,
 show_in_pos boolean not null default true,
 show_in_booking boolean not null default true,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(company_id,id),
 unique(company_id,employee_code),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id)
);
create unique index if not exists enhar_staff_company_user_uidx
 on public.enhar_staff(company_id,user_id) where user_id is not null;

create table if not exists public.enhar_staff_permissions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 staff_id uuid not null,
 module_key text not null,
 can_view boolean not null default false,
 can_create boolean not null default false,
 can_update boolean not null default false,
 can_delete boolean not null default false,
 can_approve boolean not null default false,
 can_manage_settings boolean not null default false,
 created_at timestamptz not null default now(),
 unique(company_id,staff_id,module_key),
 foreign key(company_id,staff_id) references public.enhar_staff(company_id,id) on delete cascade
);

-- Customer prepaid wallet: every deposit/use/refund is an immutable ledger row.
create table if not exists public.enhar_customer_wallets (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 customer_id uuid not null,
 balance numeric(14,2) not null default 0 check(balance >= 0),
 updated_at timestamptz not null default now(),
 unique(company_id,customer_id),
 foreign key(company_id,customer_id) references public.enhar_customers(company_id,id) on delete cascade
);
create table if not exists public.enhar_customer_wallet_transactions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 wallet_id uuid not null,
 customer_id uuid not null,
 transaction_type text not null check(transaction_type in ('DEPOSIT','REDEEM','REFUND','ADJUSTMENT')),
 amount numeric(14,2) not null check(amount > 0),
 balance_after numeric(14,2) not null check(balance_after >= 0),
 payment_method text,
 reference_type text,
 reference_id uuid,
 notes text,
 created_by uuid default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 foreign key(company_id,wallet_id) references public.enhar_customer_wallets(company_id,id),
 foreign key(company_id,customer_id) references public.enhar_customers(company_id,id)
);
create index if not exists enhar_wallet_customer_history_idx
 on public.enhar_customer_wallet_transactions(company_id,customer_id,created_at desc);

-- Appointment calendar and assignment of service provider.
create table if not exists public.enhar_appointments (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 customer_id uuid,
 service_product_id uuid,
 staff_id uuid,
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 status text not null default 'BOOKED'
   check(status in ('BOOKED','CONFIRMED','ARRIVED','IN_SERVICE','COMPLETED','CANCELLED','NO_SHOW')),
 source text not null default 'MANUAL',
 notes text,
 invoice_id uuid,
 created_by uuid default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(ends_at > starts_at),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 foreign key(company_id,customer_id) references public.enhar_customers(company_id,id),
 foreign key(company_id,service_product_id) references public.enhar_products(company_id,id),
 foreign key(company_id,staff_id) references public.enhar_staff(company_id,id)
);
create index if not exists enhar_appointments_calendar_idx
 on public.enhar_appointments(company_id,branch_id,starts_at,status);

-- POS category visibility/order and saved screen preferences.
alter table public.enhar_item_categories
 add column if not exists sort_order integer not null default 100,
 add column if not exists show_in_pos boolean not null default true,
 add column if not exists show_in_booking boolean not null default false;

create table if not exists public.enhar_pos_preferences (
 company_id uuid primary key references public.enhar_companies(id) on delete cascade,
 theme_default text not null default 'dark' check(theme_default in ('dark','light')),
 default_item_view text not null default 'SERVICE' check(default_item_view in ('PRODUCT','SERVICE','ALL')),
 pricing_mode text not null default 'RETAIL' check(pricing_mode in ('RETAIL','WHOLESALE')),
 require_cash_session boolean not null default true,
 allow_credit_sale boolean not null default false,
 allow_customer_wallet boolean not null default true,
 allow_line_discount boolean not null default true,
 allow_invoice_discount boolean not null default true,
 show_images boolean not null default true,
 updated_at timestamptz not null default now()
);

-- Receipt layout configuration. Existing invoice settings are retained.
alter table public.enhar_invoice_settings
 add column if not exists show_invoice_number boolean not null default true,
 add column if not exists show_invoice_date boolean not null default true,
 add column if not exists show_seller boolean not null default true,
 add column if not exists show_customer_phone boolean not null default true,
 add column if not exists show_customer_vat boolean not null default false,
 add column if not exists show_item_sku boolean not null default false,
 add column if not exists show_item_discount boolean not null default true,
 add column if not exists show_subtotal boolean not null default true,
 add column if not exists show_discount_total boolean not null default true,
 add column if not exists show_payment_details boolean not null default true,
 add column if not exists header_text text,
 add column if not exists qr_enabled boolean not null default true,
 add column if not exists language text not null default 'ar' check(language in ('ar','en','both'));

-- Stock counts and warehouse vouchers.
create table if not exists public.enhar_stock_counts (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 warehouse_id uuid not null,
 count_number text not null,
 count_date date not null default (now() at time zone 'Asia/Riyadh')::date,
 status text not null default 'DRAFT' check(status in ('DRAFT','IN_PROGRESS','COMPLETED','APPROVED','CANCELLED')),
 notes text,
 created_by uuid default auth.uid() references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 unique(company_id,id),
 unique(company_id,count_number),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 foreign key(company_id,warehouse_id) references public.enhar_warehouses(company_id,id)
);
create table if not exists public.enhar_stock_count_lines (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 count_id uuid not null,
 product_id uuid not null,
 system_quantity numeric(14,3) not null default 0,
 counted_quantity numeric(14,3),
 difference_quantity numeric(14,3),
 notes text,
 unique(company_id,count_id,product_id),
 foreign key(company_id,count_id) references public.enhar_stock_counts(company_id,id) on delete cascade,
 foreign key(company_id,product_id) references public.enhar_products(company_id,id)
);
create table if not exists public.enhar_stock_vouchers (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 warehouse_id uuid not null,
 voucher_number text not null,
 voucher_type text not null check(voucher_type in ('RECEIPT','ISSUE','TRANSFER_IN','TRANSFER_OUT','ADJUSTMENT','RETURN')),
 status text not null default 'DRAFT' check(status in ('DRAFT','POSTED','VOID')),
 voucher_date date not null default (now() at time zone 'Asia/Riyadh')::date,
 reason text,
 notes text,
 created_by uuid default auth.uid() references auth.users(id),
 posted_by uuid references auth.users(id),
 posted_at timestamptz,
 unique(company_id,id),
 unique(company_id,voucher_number),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 foreign key(company_id,warehouse_id) references public.enhar_warehouses(company_id,id)
);
create table if not exists public.enhar_stock_voucher_lines (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 voucher_id uuid not null,
 product_id uuid not null,
 quantity numeric(14,3) not null check(quantity > 0),
 unit_cost numeric(14,4) not null default 0,
 notes text,
 foreign key(company_id,voucher_id) references public.enhar_stock_vouchers(company_id,id) on delete cascade,
 foreign key(company_id,product_id) references public.enhar_products(company_id,id)
);

-- Supplier payment ledger.
create table if not exists public.enhar_supplier_payments (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 supplier_id uuid not null,
 payment_number text not null,
 payment_date date not null default (now() at time zone 'Asia/Riyadh')::date,
 amount numeric(14,2) not null check(amount > 0),
 payment_method text not null default 'CASH',
 reference text,
 notes text,
 created_by uuid default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 unique(company_id,payment_number),
 foreign key(company_id,supplier_id) references public.enhar_suppliers(company_id,id)
);

-- Shared RLS policy: members can read; company admins can maintain sensitive records.
do $$
declare t text;
begin
 foreach t in array array[
  'enhar_staff','enhar_staff_permissions','enhar_customer_wallets',
  'enhar_customer_wallet_transactions','enhar_appointments',
  'enhar_pos_preferences','enhar_stock_counts','enhar_stock_count_lines',
  'enhar_stock_vouchers','enhar_stock_voucher_lines','enhar_supplier_payments'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
  execute format('drop policy if exists tenant_member_read on public.%I',t);
  execute format('drop policy if exists tenant_admin_write on public.%I',t);
  execute format('create policy tenant_member_read on public.%I for select to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin())',t);
  execute format('create policy tenant_admin_write on public.%I for all to authenticated using (public.enhar_is_company_admin(company_id) or public.is_platform_admin()) with check (public.enhar_is_company_admin(company_id) or public.is_platform_admin())',t);
 end loop;
end $$;

alter table public.enhar_item_categories enable row level security;
alter table public.enhar_products enable row level security;

commit;
