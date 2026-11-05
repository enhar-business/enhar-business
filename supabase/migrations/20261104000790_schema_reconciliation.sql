-- ENHAR BUSINESS | Canonical schema compatibility repair
-- Version 20261104001600. Additive-only reconciliation for the historical
-- alternate CREATE TABLE IF NOT EXISTS definitions. Never drops business rows.
begin;

-- Catalog and contacts: columns used by both legacy and current screens/RPCs.
alter table public.enhar_customers
  add column if not exists customer_code text,
  add column if not exists customer_type text not null default 'INDIVIDUAL',
  add column if not exists credit_limit numeric(14,2) not null default 0,
  add column if not exists notes text;
update public.enhar_customers
set customer_code = coalesce(nullif(customer_code,''),'CUS-'||upper(substr(replace(id::text,'-',''),1,10)))
where customer_code is null or customer_code='';

alter table public.enhar_suppliers
  add column if not exists supplier_code text,
  add column if not exists commercial_registration text,
  add column if not exists notes text;
update public.enhar_suppliers
set supplier_code = coalesce(nullif(supplier_code,''),'SUP-'||upper(substr(replace(id::text,'-',''),1,10)))
where supplier_code is null or supplier_code='';

alter table public.enhar_products
  add column if not exists name_en text,
  add column if not exists tax_rate numeric(5,2) not null default 15,
  add column if not exists category_id uuid,
  add column if not exists barcode text,
  add column if not exists description text,
  add column if not exists image_url text,
  add column if not exists is_bundle boolean not null default false,
  add column if not exists allow_retail boolean not null default true,
  add column if not exists allow_wholesale boolean not null default false,
  add column if not exists show_in_pos boolean not null default true,
  add column if not exists show_in_booking boolean not null default false,
  add column if not exists min_stock numeric(14,3) not null default 0,
  add column if not exists default_supplier_id uuid,
  add column if not exists wholesale_price numeric(14,4) not null default 0,
  add column if not exists updated_at timestamptz not null default now();

alter table public.enhar_product_branches
  add column if not exists is_available boolean not null default true;

-- Invoice headers and lines: keep both naming conventions until UI/RPC callers
-- have been migrated to one canonical contract.
alter table public.enhar_sales_invoices
  add column if not exists warehouse_id uuid,
  add column if not exists cash_session_id uuid,
  add column if not exists discount_total numeric(14,2) not null default 0,
  add column if not exists payment_method text;
alter table public.enhar_purchase_invoices
  add column if not exists warehouse_id uuid,
  add column if not exists supplier_invoice_number text;
alter table public.enhar_sales_invoice_lines
  add column if not exists discount numeric(14,2) not null default 0,
  add column if not exists discount_amount numeric(14,2) not null default 0,
  add column if not exists tax_amount numeric(14,2) not null default 0;
alter table public.enhar_purchase_invoice_lines
  add column if not exists description text,
  add column if not exists discount numeric(14,2) not null default 0,
  add column if not exists tax_rate numeric(5,2) not null default 15,
  add column if not exists tax_amount numeric(14,2) not null default 0;

-- Cash sessions: the cashbox and register screens used different column names.
alter table public.enhar_cash_sessions
  add column if not exists cashbox_id uuid,
  add column if not exists register_id uuid,
  add column if not exists actual_amount numeric(14,2),
  add column if not exists difference numeric(14,2),
  add column if not exists counted_amount numeric(14,2),
  add column if not exists difference_amount numeric(14,2),
  add column if not exists notes text,
  add column if not exists closing_notes text;
alter table public.enhar_cash_movements
  add column if not exists reference text;

-- Receipt preferences used by the different UI iterations.
alter table public.enhar_invoice_settings
  add column if not exists company_name text,
  add column if not exists vat_number text,
  add column if not exists commercial_registration text,
  add column if not exists address text,
  add column if not exists show_logo boolean not null default true,
  add column if not exists show_customer_details boolean not null default true,
  add column if not exists show_item_barcode boolean not null default false,
  add column if not exists show_tax_breakdown boolean not null default true,
  add column if not exists show_company_address boolean not null default true,
  add column if not exists show_vat_number boolean not null default true,
  add column if not exists show_cr_number boolean not null default true,
  add column if not exists show_customer_data boolean not null default true,
  add column if not exists show_cashier boolean not null default true,
  add column if not exists show_branch boolean not null default true,
  add column if not exists show_payment_method boolean not null default true,
  add column if not exists show_qr_code boolean not null default true,
  add column if not exists show_seller boolean not null default true,
  add column if not exists show_customer_phone boolean not null default false,
  add column if not exists show_customer_vat boolean not null default false,
  add column if not exists show_item_sku boolean not null default false,
  add column if not exists show_item_discount boolean not null default true,
  add column if not exists show_subtotal boolean not null default true,
  add column if not exists show_discount_total boolean not null default true,
  add column if not exists show_payment_details boolean not null default true,
  add column if not exists header_text text,
  add column if not exists qr_enabled boolean not null default true,
  add column if not exists language text not null default 'ar';

-- Staff aliases. Both old and new frontend names remain readable during migration.
alter table public.enhar_staff
  add column if not exists auth_user_id uuid references auth.users(id) on delete set null,
  add column if not exists user_id uuid references auth.users(id) on delete set null,
  add column if not exists staff_code text,
  add column if not exists employee_code text,
  add column if not exists can_appear_in_pos boolean not null default false,
  add column if not exists can_appear_in_booking boolean not null default false,
  add column if not exists can_perform_services boolean not null default false,
  add column if not exists can_be_cashier boolean not null default false,
  add column if not exists show_in_pos boolean not null default true,
  add column if not exists show_in_booking boolean not null default true,
  add column if not exists commission_rate numeric(7,3) not null default 0;
update public.enhar_staff
set auth_user_id=coalesce(auth_user_id,user_id),
    user_id=coalesce(user_id,auth_user_id),
    staff_code=coalesce(nullif(staff_code,''),employee_code,'EMP-'||upper(substr(replace(id::text,'-',''),1,10))),
    employee_code=coalesce(nullif(employee_code,''),staff_code,'EMP-'||upper(substr(replace(id::text,'-',''),1,10))),
    can_perform_services=can_perform_services or can_appear_in_booking or show_in_booking,
    can_appear_in_booking=can_appear_in_booking or can_perform_services or show_in_booking,
    show_in_booking=show_in_booking or can_perform_services or can_appear_in_booking,
    can_appear_in_pos=can_appear_in_pos or show_in_pos,
    show_in_pos=show_in_pos or can_appear_in_pos;

-- Booking aliases and a trigger keep required legacy fields populated on inserts.
alter table public.enhar_appointments
  add column if not exists staff_id uuid,
  add column if not exists service_staff_id uuid,
  add column if not exists appointment_number text,
  add column if not exists invoice_id uuid;
update public.enhar_appointments
set staff_id=coalesce(staff_id,service_staff_id),
    service_staff_id=coalesce(service_staff_id,staff_id),
    appointment_number=coalesce(nullif(appointment_number,''),'APT-'||upper(substr(replace(id::text,'-',''),1,12)))
where staff_id is null or service_staff_id is null or appointment_number is null;
create or replace function public.enhar_sync_appointment_compat()
returns trigger language plpgsql set search_path=''
as $$
begin
  new.staff_id:=coalesce(new.staff_id,new.service_staff_id);
  new.service_staff_id:=coalesce(new.service_staff_id,new.staff_id);
  if new.appointment_number is null or new.appointment_number='' then
    new.appointment_number:='APT-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  end if;
  return new;
end $$;
drop trigger if exists enhar_appointments_compat_sync on public.enhar_appointments;
create trigger enhar_appointments_compat_sync
before insert or update of staff_id,service_staff_id,appointment_number
on public.enhar_appointments
for each row execute function public.enhar_sync_appointment_compat();

-- Wallet: normalize both ledger layouts without deleting transactions.
create table if not exists public.enhar_customer_wallets (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 customer_id uuid not null,
 balance numeric(14,2) not null default 0 check(balance>=0),
 updated_at timestamptz not null default now(),
 unique(company_id,id),
 unique(company_id,customer_id),
 foreign key(company_id,customer_id) references public.enhar_customers(company_id,id) on delete cascade
);
alter table public.enhar_customer_wallet_transactions
  add column if not exists wallet_id uuid,
  add column if not exists balance_after numeric(14,2),
  add column if not exists payment_method text,
  add column if not exists branch_id uuid;
do $$
declare c record;
begin
 for c in
  select conname from pg_constraint
  where conrelid='public.enhar_customer_wallet_transactions'::regclass
    and contype='c' and pg_get_constraintdef(oid) ilike '%transaction_type%'
 loop
  execute format('alter table public.enhar_customer_wallet_transactions drop constraint %I',c.conname);
 end loop;
end $$;
alter table public.enhar_customer_wallet_transactions
  add constraint enhar_wallet_transaction_type_compat_check
  check(transaction_type in ('DEPOSIT','SALE_REDEMPTION','REDEEM','REFUND','ADJUSTMENT'));
insert into public.enhar_customer_wallets(company_id,customer_id,balance)
select t.company_id,t.customer_id,
 greatest(0,round(sum(case
   when t.transaction_type in ('DEPOSIT','REFUND','ADJUSTMENT') then t.amount
   when t.transaction_type in ('SALE_REDEMPTION','REDEEM') then -t.amount
   else 0 end),2))
from public.enhar_customer_wallet_transactions t
group by t.company_id,t.customer_id
on conflict(company_id,customer_id) do nothing;
update public.enhar_customer_wallet_transactions t
set wallet_id=w.id,
    balance_after=coalesce(t.balance_after,w.balance),
    payment_method=coalesce(t.payment_method,'LEGACY')
from public.enhar_customer_wallets w
where w.company_id=t.company_id and w.customer_id=t.customer_id
  and (t.wallet_id is null or t.balance_after is null or t.payment_method is null);
do $$
begin
 if not exists(select 1 from pg_constraint where conname='enhar_wallet_tx_company_wallet_fk') then
  alter table public.enhar_customer_wallet_transactions
   add constraint enhar_wallet_tx_company_wallet_fk
   foreign key(company_id,wallet_id) references public.enhar_customer_wallets(company_id,id);
 end if;
end $$;

-- Stock count aliases used by both count screens and posting RPCs.
alter table public.enhar_stock_count_lines
  add column if not exists count_id uuid,
  add column if not exists stock_count_id uuid,
  add column if not exists difference_quantity numeric(14,3),
  add column if not exists unit_cost numeric(14,4) not null default 0,
  add column if not exists created_at timestamptz not null default now();
update public.enhar_stock_count_lines
set count_id=coalesce(count_id,stock_count_id),
    stock_count_id=coalesce(stock_count_id,count_id),
    difference_quantity=coalesce(difference_quantity,coalesce(counted_quantity,system_quantity)-system_quantity);
create unique index if not exists enhar_stock_count_lines_company_count_product_uidx
 on public.enhar_stock_count_lines(company_id,count_id,product_id)
 where count_id is not null;
do $$
begin
 if not exists(select 1 from pg_constraint where conname='enhar_stock_count_lines_count_compat_fk') then
  alter table public.enhar_stock_count_lines
   add constraint enhar_stock_count_lines_count_compat_fk
   foreign key(company_id,count_id) references public.enhar_stock_counts(company_id,id) on delete cascade;
 end if;
end $$;

-- Product/category compatibility for old catalog layouts.
do $$
begin
 if not exists(select 1 from pg_constraint where conname='enhar_products_company_category_reconcile_fk') then
  alter table public.enhar_products
   add constraint enhar_products_company_category_reconcile_fk
   foreign key(company_id,category_id) references public.enhar_item_categories(company_id,id);
 end if;
 if not exists(select 1 from pg_constraint where conname='enhar_products_company_supplier_reconcile_fk') then
  alter table public.enhar_products
   add constraint enhar_products_company_supplier_reconcile_fk
   foreign key(company_id,default_supplier_id) references public.enhar_suppliers(company_id,id);
 end if;
end $$;

create index if not exists enhar_sales_invoices_company_warehouse_idx
 on public.enhar_sales_invoices(company_id,warehouse_id);
create index if not exists enhar_purchase_invoices_company_warehouse_idx
 on public.enhar_purchase_invoices(company_id,warehouse_id);
create index if not exists enhar_staff_company_employee_code_idx
 on public.enhar_staff(company_id,employee_code);
create index if not exists enhar_appointments_company_staff_start_idx
 on public.enhar_appointments(company_id,staff_id,starts_at);

commit;
notify pgrst, 'reload schema';
