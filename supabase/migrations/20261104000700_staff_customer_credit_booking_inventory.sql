-- ENHAR BUSINESS | Staff roles, customer wallet, bookings, inventory counts and stock documents
-- Additive migration: does not drop existing business data.
begin;

-- Ensure composite keys exist even when earlier tables were created by an older migration.
create unique index if not exists enhar_products_company_id_uidx on public.enhar_products(company_id,id);
create unique index if not exists enhar_customers_company_id_uidx on public.enhar_customers(company_id,id);
create unique index if not exists enhar_suppliers_company_id_uidx on public.enhar_suppliers(company_id,id);
create unique index if not exists enhar_branches_company_id_uidx on public.enhar_branches(company_id,id);
create unique index if not exists enhar_warehouses_company_id_uidx on public.enhar_warehouses(company_id,id);

-- Staff directory and role-based permissions. A staff record may exist before an auth invitation.
create table if not exists public.enhar_staff (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 auth_user_id uuid references auth.users(id) on delete set null,
 branch_id uuid,
 staff_code text not null,
 full_name text not null,
 phone text,
 email text,
 job_title text,
 staff_type text not null default 'CASHIER'
  check (staff_type in ('SERVICE_PROVIDER','CASHIER','ACCOUNTANT','ACCOUNTING_MANAGER','WAREHOUSE_KEEPER','BRANCH_MANAGER','ADMIN')),
 is_active boolean not null default true,
 can_appear_in_pos boolean not null default false,
 can_appear_in_booking boolean not null default false,
 commission_rate numeric(7,3) not null default 0 check(commission_rate between 0 and 100),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(company_id,id),
 unique(company_id,staff_code),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id)
);
create unique index if not exists enhar_staff_company_auth_user_uidx
 on public.enhar_staff(company_id,auth_user_id) where auth_user_id is not null;

create table if not exists public.enhar_staff_role_permissions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 role_key text not null,
 module_key text not null,
 can_view boolean not null default false,
 can_create boolean not null default false,
 can_update boolean not null default false,
 can_delete boolean not null default false,
 can_approve boolean not null default false,
 can_manage_settings boolean not null default false,
 unique(company_id,role_key,module_key)
);

create table if not exists public.enhar_staff_user_roles (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 staff_id uuid not null,
 auth_user_id uuid not null references auth.users(id) on delete cascade,
 role_key text not null,
 branch_id uuid,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(company_id,staff_id,role_key),
 foreign key(company_id,staff_id) references public.enhar_staff(company_id,id) on delete cascade,
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id)
);

-- Customer wallet is a ledger, never a manually overwritten balance.
create table if not exists public.enhar_customer_wallet_transactions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 customer_id uuid not null,
 branch_id uuid,
 transaction_type text not null check(transaction_type in ('DEPOSIT','SALE_REDEMPTION','REFUND','ADJUSTMENT')),
 amount numeric(14,2) not null check(amount>0),
 reference_type text,
 reference_id uuid,
 notes text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 foreign key(company_id,customer_id) references public.enhar_customers(company_id,id),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id)
);
create index if not exists enhar_customer_wallet_customer_idx
 on public.enhar_customer_wallet_transactions(company_id,customer_id,created_at desc);

-- Booking calendar.
create table if not exists public.enhar_appointments (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 customer_id uuid,
 service_product_id uuid,
 service_staff_id uuid,
 appointment_number text not null,
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 status text not null default 'BOOKED'
  check(status in ('BOOKED','CONFIRMED','CHECKED_IN','IN_SERVICE','COMPLETED','CANCELLED','NO_SHOW')),
 source text not null default 'MANUAL',
 notes text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(company_id,id),
 unique(company_id,appointment_number),
 check(ends_at>starts_at),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 foreign key(company_id,customer_id) references public.enhar_customers(company_id,id),
 foreign key(company_id,service_product_id) references public.enhar_products(company_id,id),
 foreign key(company_id,service_staff_id) references public.enhar_staff(company_id,id)
);
create index if not exists enhar_appointments_calendar_idx
 on public.enhar_appointments(company_id,branch_id,starts_at,ends_at);

-- Physical inventory count: header and counted lines; approval is a separate state transition.
create table if not exists public.enhar_stock_counts (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 warehouse_id uuid not null,
 count_number text not null,
 count_date date not null default (now() at time zone 'Asia/Riyadh')::date,
 status text not null default 'DRAFT' check(status in ('DRAFT','IN_PROGRESS','SUBMITTED','APPROVED','CANCELLED')),
 notes text,
 created_by uuid references auth.users(id),
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
 stock_count_id uuid not null,
 product_id uuid not null,
 system_quantity numeric(14,3) not null default 0,
 counted_quantity numeric(14,3),
 unit_cost numeric(14,4) not null default 0,
 notes text,
 created_at timestamptz not null default now(),
 unique(company_id,stock_count_id,product_id),
 foreign key(company_id,stock_count_id) references public.enhar_stock_counts(company_id,id) on delete cascade,
 foreign key(company_id,product_id) references public.enhar_products(company_id,id),
 check(counted_quantity is null or counted_quantity>=0)
);

-- Stock documents for receipts, issues and inter-warehouse transfers.
create table if not exists public.enhar_stock_documents (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 warehouse_id uuid not null,
 destination_warehouse_id uuid,
 document_number text not null,
 document_type text not null check(document_type in ('RECEIPT','ISSUE','TRANSFER','ADJUSTMENT','SALES_RETURN','PURCHASE_RETURN')),
 status text not null default 'DRAFT' check(status in ('DRAFT','POSTED','VOID')),
 document_date date not null default (now() at time zone 'Asia/Riyadh')::date,
 reason text,
 notes text,
 created_by uuid references auth.users(id),
 posted_by uuid references auth.users(id),
 posted_at timestamptz,
 created_at timestamptz not null default now(),
 unique(company_id,id),
 unique(company_id,document_number),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 foreign key(company_id,warehouse_id) references public.enhar_warehouses(company_id,id),
 foreign key(company_id,destination_warehouse_id) references public.enhar_warehouses(company_id,id),
 check((document_type='TRANSFER' and destination_warehouse_id is not null and destination_warehouse_id<>warehouse_id)
    or (document_type<>'TRANSFER' and destination_warehouse_id is null))
);
create table if not exists public.enhar_stock_document_lines (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 document_id uuid not null,
 product_id uuid not null,
 quantity numeric(14,3) not null check(quantity>0),
 unit_cost numeric(14,4) not null default 0 check(unit_cost>=0),
 notes text,
 created_at timestamptz not null default now(),
 foreign key(company_id,document_id) references public.enhar_stock_documents(company_id,id) on delete cascade,
 foreign key(company_id,product_id) references public.enhar_products(company_id,id)
);

-- Ensure catalog settings tables exist when upgrading an older installation.
create table if not exists public.enhar_item_categories (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 category_type text not null check(category_type in ('PRODUCT','SERVICE')),
 name_ar text not null,
 name_en text,
 description text,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(company_id,id),
 unique(company_id,category_type,name_ar)
);

create table if not exists public.enhar_invoice_settings (
 company_id uuid primary key references public.enhar_companies(id) on delete cascade,
 paper_size text not null default 'A4',
 show_logo boolean not null default true,
 footer_text text,
 updated_at timestamptz not null default now()
);

-- Customer display and POS category layout preferences.
alter table public.enhar_products
 add column if not exists pos_sort_order integer not null default 0,
 add column if not exists pos_tile_color text,
 add column if not exists service_duration_minutes integer,
 add column if not exists requires_booking boolean not null default false;

alter table public.enhar_invoice_settings
 add column if not exists show_seller boolean not null default true,
 add column if not exists show_cashier boolean not null default true,
 add column if not exists show_branch boolean not null default true,
 add column if not exists show_payment_method boolean not null default true,
 add column if not exists show_customer_phone boolean not null default false,
 add column if not exists show_qr_code boolean not null default true,
 add column if not exists header_text text,
 add column if not exists receipt_language text not null default 'ar';

create table if not exists public.enhar_pos_category_preferences (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid,
 category_id uuid not null,
 is_visible boolean not null default true,
 sort_order integer not null default 0,
 created_at timestamptz not null default now(),
 unique(company_id,branch_id,category_id),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 foreign key(company_id,category_id) references public.enhar_item_categories(company_id,id)
);

-- Safe balance view: credits are deposits/refunds; debits are redemptions.
create or replace view public.enhar_customer_wallet_balances
with (security_invoker=true) as
select company_id,customer_id,
 coalesce(sum(case when transaction_type in ('DEPOSIT','REFUND') then amount
                   when transaction_type='SALE_REDEMPTION' then -amount
                   when transaction_type='ADJUSTMENT' then amount end),0)::numeric(14,2) as balance
from public.enhar_customer_wallet_transactions
group by company_id,customer_id;

-- Basic RLS: company members can read; company admins/platform admin manage.
do $$
declare t text;
begin
 foreach t in array array[
  'enhar_staff','enhar_staff_role_permissions','enhar_staff_user_roles',
  'enhar_customer_wallet_transactions','enhar_appointments',
  'enhar_stock_counts','enhar_stock_count_lines',
  'enhar_stock_documents','enhar_stock_document_lines',
  'enhar_pos_category_preferences'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
  execute format('drop policy if exists enhar_tenant_read on public.%I',t);
  execute format('drop policy if exists enhar_tenant_admin_write on public.%I',t);
  execute format('create policy enhar_tenant_read on public.%I for select to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin())',t);
  execute format('create policy enhar_tenant_admin_write on public.%I for all to authenticated using (public.enhar_is_company_admin(company_id) or public.is_platform_admin()) with check (public.enhar_is_company_admin(company_id) or public.is_platform_admin())',t);
 end loop;
end $$;

grant select on public.enhar_customer_wallet_balances to authenticated;
commit;
