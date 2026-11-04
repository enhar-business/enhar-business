-- ENHAR BUSINESS | Core operating tables (Phase 1)
-- Run in Supabase SQL Editor after 20261104000200_tenant_foundation.sql.
-- Tenant-scoped tables with RLS; all business rows carry company_id.

begin;

create table if not exists public.enhar_customers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  customer_code text not null,
  name text not null,
  phone text,
  email text,
  vat_number text,
  address jsonb not null default '{}'::jsonb,
  opening_balance numeric(14,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(company_id, id),
  unique(company_id, customer_code)
);

create table if not exists public.enhar_suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  supplier_code text not null,
  name text not null,
  phone text,
  email text,
  vat_number text,
  address jsonb not null default '{}'::jsonb,
  opening_balance numeric(14,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(company_id, id),
  unique(company_id, supplier_code)
);

create table if not exists public.enhar_products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  sku text not null,
  name_ar text not null,
  name_en text,
  item_type text not null default 'PRODUCT' check(item_type in ('PRODUCT','SERVICE')),
  tracking_type text not null default 'NONE' check(tracking_type in ('NONE','LOT','SERIAL')),
  unit_name text not null default 'حبة',
  purchase_price numeric(14,4) not null default 0 check(purchase_price >= 0),
  sale_price numeric(14,4) not null default 0 check(sale_price >= 0),
  tax_rate numeric(5,2) not null default 15 check(tax_rate between 0 and 100),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(company_id, id),
  unique(company_id, sku)
);

create table if not exists public.enhar_sales_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  branch_id uuid not null,
  warehouse_id uuid not null,
  customer_id uuid,
  invoice_number text not null,
  invoice_date date not null default (now() at time zone 'Asia/Riyadh')::date,
  status text not null default 'DRAFT' check(status in ('DRAFT','POSTED','VOID')),
  subtotal numeric(14,2) not null default 0,
  tax_total numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(company_id, id),
  unique(company_id, invoice_number),
  foreign key(company_id, branch_id) references public.enhar_branches(company_id,id),
  foreign key(company_id, warehouse_id) references public.enhar_warehouses(company_id,id),
  foreign key(company_id, customer_id) references public.enhar_customers(company_id,id)
);

create table if not exists public.enhar_sales_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  invoice_id uuid not null,
  product_id uuid not null,
  description text,
  quantity numeric(14,3) not null check(quantity > 0),
  unit_price numeric(14,4) not null check(unit_price >= 0),
  discount numeric(14,2) not null default 0 check(discount >= 0),
  tax_rate numeric(5,2) not null default 15 check(tax_rate between 0 and 100),
  line_total numeric(14,2) not null check(line_total >= 0),
  created_at timestamptz not null default now(),
  foreign key(company_id, invoice_id) references public.enhar_sales_invoices(company_id,id) on delete cascade,
  foreign key(company_id, product_id) references public.enhar_products(company_id,id)
);

create table if not exists public.enhar_purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  branch_id uuid not null,
  warehouse_id uuid not null,
  supplier_id uuid,
  invoice_number text not null,
  supplier_invoice_number text,
  invoice_date date not null default (now() at time zone 'Asia/Riyadh')::date,
  status text not null default 'DRAFT' check(status in ('DRAFT','POSTED','VOID')),
  subtotal numeric(14,2) not null default 0,
  tax_total numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(company_id,id),
  unique(company_id,invoice_number),
  foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
  foreign key(company_id,warehouse_id) references public.enhar_warehouses(company_id,id),
  foreign key(company_id,supplier_id) references public.enhar_suppliers(company_id,id)
);

create table if not exists public.enhar_purchase_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  invoice_id uuid not null,
  product_id uuid not null,
  description text,
  quantity numeric(14,3) not null check(quantity > 0),
  unit_cost numeric(14,4) not null check(unit_cost >= 0),
  discount numeric(14,2) not null default 0 check(discount >= 0),
  tax_rate numeric(5,2) not null default 15 check(tax_rate between 0 and 100),
  line_total numeric(14,2) not null check(line_total >= 0),
  created_at timestamptz not null default now(),
  foreign key(company_id,invoice_id) references public.enhar_purchase_invoices(company_id,id) on delete cascade,
  foreign key(company_id,product_id) references public.enhar_products(company_id,id)
);

create table if not exists public.enhar_stock_movements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  branch_id uuid not null,
  warehouse_id uuid not null,
  product_id uuid not null,
  movement_type text not null check(movement_type in ('OPENING','PURCHASE','SALE','PURCHASE_RETURN','SALES_RETURN','ADJUSTMENT','TRANSFER_IN','TRANSFER_OUT')),
  quantity_in numeric(14,3) not null default 0 check(quantity_in >= 0),
  quantity_out numeric(14,3) not null default 0 check(quantity_out >= 0),
  unit_cost numeric(14,4) not null default 0 check(unit_cost >= 0),
  source_type text,
  source_id uuid,
  movement_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
  foreign key(company_id,warehouse_id) references public.enhar_warehouses(company_id,id),
  foreign key(company_id,product_id) references public.enhar_products(company_id,id),
  check (quantity_in > 0 or quantity_out > 0)
);

create table if not exists public.enhar_chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  account_code text not null,
  name_ar text not null,
  name_en text,
  account_type text not null check(account_type in ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE')),
  parent_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(company_id,id),
  unique(company_id,account_code),
  foreign key(company_id,parent_id) references public.enhar_chart_of_accounts(company_id,id)
);

create table if not exists public.enhar_journal_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  entry_number text not null,
  entry_date date not null default (now() at time zone 'Asia/Riyadh')::date,
  description text not null,
  status text not null default 'DRAFT' check(status in ('DRAFT','POSTED','VOID')),
  source_type text,
  source_id uuid,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(company_id,id),
  unique(company_id,entry_number)
);

create table if not exists public.enhar_journal_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  journal_entry_id uuid not null,
  account_id uuid not null,
  description text,
  debit numeric(14,2) not null default 0 check(debit >= 0),
  credit numeric(14,2) not null default 0 check(credit >= 0),
  created_at timestamptz not null default now(),
  foreign key(company_id,journal_entry_id) references public.enhar_journal_entries(company_id,id) on delete cascade,
  foreign key(company_id,account_id) references public.enhar_chart_of_accounts(company_id,id),
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

create index if not exists enhar_customers_company_idx on public.enhar_customers(company_id);
create index if not exists enhar_suppliers_company_idx on public.enhar_suppliers(company_id);
create index if not exists enhar_products_company_idx on public.enhar_products(company_id);
create index if not exists enhar_sales_company_date_idx on public.enhar_sales_invoices(company_id,invoice_date desc);
create index if not exists enhar_purchases_company_date_idx on public.enhar_purchase_invoices(company_id,invoice_date desc);
create index if not exists enhar_stock_company_product_idx on public.enhar_stock_movements(company_id,warehouse_id,product_id,movement_at);
create index if not exists enhar_journal_company_date_idx on public.enhar_journal_entries(company_id,entry_date desc);

-- RLS: membership grants access only inside the user's own company.
do $$
declare t text;
begin
  foreach t in array array[
    'enhar_customers','enhar_suppliers','enhar_products',
    'enhar_sales_invoices','enhar_sales_invoice_lines',
    'enhar_purchase_invoices','enhar_purchase_invoice_lines',
    'enhar_stock_movements','enhar_chart_of_accounts',
    'enhar_journal_entries','enhar_journal_lines'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_member_access', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin()) with check (public.enhar_is_company_member(company_id) or public.is_platform_admin())',
      t || '_member_access', t
    );
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

commit;

-- NOTE: This phase creates secure data structures. Invoice posting, FIFO/weighted-average
-- valuation, balanced journal automation, ZATCA integration and serial/lot expiry workflows
-- require tested business-logic functions before production use.
