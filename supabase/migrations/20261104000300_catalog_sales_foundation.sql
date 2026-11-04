-- ENHAR BUSINESS | Catalog, contacts, sales and purchasing foundation
-- Migration 003. Run once in Supabase SQL Editor. Safe to re-run.
begin;

create table if not exists public.enhar_item_categories (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 category_type text not null check (category_type in ('PRODUCT','SERVICE')),
 name_ar text not null check (char_length(trim(name_ar)) between 1 and 150),
 name_en text,
 description text,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(company_id,category_type,name_ar),
 unique(id,company_id)
);

create table if not exists public.enhar_suppliers (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 name text not null,
 phone text,
 email text,
 vat_number text,
 commercial_registration text,
 address text,
 opening_balance numeric(14,2) not null default 0,
 notes text,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(id,company_id)
);

create table if not exists public.enhar_customers (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 name text not null,
 phone text,
 email text,
 vat_number text,
 address text,
 customer_type text not null default 'INDIVIDUAL' check(customer_type in ('INDIVIDUAL','BUSINESS')),
 credit_limit numeric(14,2) not null default 0 check(credit_limit>=0),
 opening_balance numeric(14,2) not null default 0,
 notes text,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(id,company_id)
);

create table if not exists public.enhar_products (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 sku text not null,
 name_ar text not null,
 item_type text not null check(item_type in ('PRODUCT','SERVICE')),
 tracking_type text not null default 'NONE' check(tracking_type in ('NONE','LOT','SERIAL','EXPIRY')),
 category_id uuid,
 barcode text,
 description text,
 image_url text,
 sale_price numeric(14,2) not null default 0 check(sale_price>=0),
 wholesale_price numeric(14,2) not null default 0 check(wholesale_price>=0),
 purchase_price numeric(14,2) not null default 0 check(purchase_price>=0),
 unit_name text not null default 'حبة',
 min_stock numeric(14,3) not null default 0 check(min_stock>=0),
 default_supplier_id uuid,
 allow_retail boolean not null default true,
 allow_wholesale boolean not null default false,
 show_in_pos boolean not null default true,
 show_in_booking boolean not null default false,
 is_bundle boolean not null default false,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(company_id,sku),
 unique(id,company_id),
 constraint enhar_products_category_company_fk foreign key(category_id,company_id)
  references public.enhar_item_categories(id,company_id),
 constraint enhar_products_supplier_company_fk foreign key(default_supplier_id,company_id)
  references public.enhar_suppliers(id,company_id)
);

create table if not exists public.enhar_product_branches (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 product_id uuid not null,
 branch_id uuid not null,
 created_at timestamptz not null default now(),
 unique(product_id,branch_id),
 foreign key(product_id,company_id) references public.enhar_products(id,company_id) on delete cascade,
 foreign key(branch_id,company_id) references public.enhar_branches(id,company_id) on delete cascade
);

create table if not exists public.enhar_invoice_settings (
 company_id uuid primary key references public.enhar_companies(id) on delete cascade,
 paper_size text not null default 'A4' check(paper_size in ('A4','THERMAL_80','THERMAL_58')),
 company_name text,
 vat_number text,
 commercial_registration text,
 address text,
 footer_text text,
 updated_at timestamptz not null default now()
);

create table if not exists public.enhar_promotions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 name text not null,
 type text not null check(type in ('PERCENT','FIXED','PRICE')),
 value numeric(14,2) not null check(value>=0),
 starts_on date,
 ends_on date,
 branch_id uuid,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 check(ends_on is null or starts_on is null or ends_on>=starts_on),
 foreign key(branch_id,company_id) references public.enhar_branches(id,company_id)
);

create table if not exists public.enhar_sales_invoices (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 invoice_number text not null,
 invoice_date date not null default (now() at time zone 'Asia/Riyadh')::date,
 customer_id uuid,
 cash_session_id uuid,
 status text not null default 'DRAFT' check(status in ('DRAFT','POSTED','PAID','PARTIAL','VOID','REFUNDED')),
 subtotal numeric(14,2) not null default 0,
 discount_total numeric(14,2) not null default 0,
 tax_total numeric(14,2) not null default 0,
 grand_total numeric(14,2) not null default 0,
 payment_method text,
 notes text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(company_id,invoice_number),
 foreign key(branch_id,company_id) references public.enhar_branches(id,company_id),
 foreign key(customer_id,company_id) references public.enhar_customers(id,company_id)
);

create table if not exists public.enhar_sales_invoice_lines (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 invoice_id uuid not null,
 product_id uuid not null,
 description text,
 quantity numeric(14,3) not null check(quantity>0),
 unit_price numeric(14,2) not null check(unit_price>=0),
 discount_amount numeric(14,2) not null default 0 check(discount_amount>=0),
 tax_rate numeric(7,4) not null default 0,
 tax_amount numeric(14,2) not null default 0,
 line_total numeric(14,2) not null,
 created_at timestamptz not null default now(),
 foreign key(invoice_id) references public.enhar_sales_invoices(id) on delete cascade,
 foreign key(product_id,company_id) references public.enhar_products(id,company_id)
);

create table if not exists public.enhar_purchase_invoices (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 supplier_id uuid,
 invoice_number text not null,
 invoice_date date not null default (now() at time zone 'Asia/Riyadh')::date,
 status text not null default 'DRAFT' check(status in ('DRAFT','POSTED','PAID','PARTIAL','VOID')),
 subtotal numeric(14,2) not null default 0,
 tax_total numeric(14,2) not null default 0,
 grand_total numeric(14,2) not null default 0,
 notes text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(company_id,invoice_number),
 foreign key(branch_id,company_id) references public.enhar_branches(id,company_id),
 foreign key(supplier_id,company_id) references public.enhar_suppliers(id,company_id)
);

create table if not exists public.enhar_purchase_invoice_lines (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 invoice_id uuid not null references public.enhar_purchase_invoices(id) on delete cascade,
 product_id uuid not null,
 quantity numeric(14,3) not null check(quantity>0),
 unit_cost numeric(14,2) not null check(unit_cost>=0),
 tax_amount numeric(14,2) not null default 0,
 line_total numeric(14,2) not null,
 created_at timestamptz not null default now(),
 foreign key(product_id,company_id) references public.enhar_products(id,company_id)
);

-- Upgrade an older pre-existing products table without deleting its data.
alter table public.enhar_products
 add column if not exists barcode text;

create index if not exists enhar_products_company_type_idx on public.enhar_products(company_id,item_type,is_active);
create index if not exists enhar_products_company_barcode_idx on public.enhar_products(company_id,barcode);
create index if not exists enhar_sales_company_date_idx on public.enhar_sales_invoices(company_id,invoice_date desc);
create index if not exists enhar_purchase_company_date_idx on public.enhar_purchase_invoices(company_id,invoice_date desc);

do $$
declare t text;
begin
 foreach t in array array[
  'enhar_item_categories','enhar_suppliers','enhar_customers','enhar_products',
  'enhar_product_branches','enhar_invoice_settings','enhar_promotions',
  'enhar_sales_invoices','enhar_sales_invoice_lines',
  'enhar_purchase_invoices','enhar_purchase_invoice_lines'
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

commit;
