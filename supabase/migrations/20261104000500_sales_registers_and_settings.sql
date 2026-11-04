-- ENHAR BUSINESS | Sales registers, cash sessions, invoice preferences and promotions
-- Run after tenant foundation (002), core business tables (003) and catalog (004).
begin;

create table if not exists public.enhar_cashboxes (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 branch_id uuid not null,
 code text not null,
 name_ar text not null,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(company_id,id), unique(company_id,code),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id)
);

create table if not exists public.enhar_cash_sessions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 cashbox_id uuid not null,
 branch_id uuid not null,
 opened_by uuid not null default auth.uid() references auth.users(id),
 closed_by uuid references auth.users(id),
 opened_at timestamptz not null default now(),
 closed_at timestamptz,
 status text not null default 'OPEN' check(status in ('OPEN','CLOSED')),
 opening_amount numeric(14,2) not null default 0 check(opening_amount>=0),
 expected_amount numeric(14,2) not null default 0,
 actual_amount numeric(14,2),
 difference numeric(14,2),
 notes text,
 unique(company_id,id),
 foreign key(company_id,cashbox_id) references public.enhar_cashboxes(company_id,id),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 check((status='OPEN' and closed_at is null) or (status='CLOSED' and closed_at is not null))
);

create table if not exists public.enhar_cash_movements (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 session_id uuid not null,
 movement_type text not null check(movement_type in ('OPENING','SALE','REFUND','CASH_IN','CASH_OUT','CLOSING')),
 amount numeric(14,2) not null check(amount>=0),
 payment_method text not null default 'CASH',
 notes text,
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 foreign key(company_id,session_id) references public.enhar_cash_sessions(company_id,id) on delete cascade
);

create table if not exists public.enhar_cash_settings (
 company_id uuid primary key references public.enhar_companies(id) on delete cascade,
 allow_open boolean not null default true,
 allow_close boolean not null default true,
 require_balance_approval boolean not null default false,
 updated_at timestamptz not null default now()
);

create table if not exists public.enhar_invoice_settings (
 company_id uuid primary key references public.enhar_companies(id) on delete cascade,
 paper_size text not null default 'A4' check(paper_size in ('A4','THERMAL_80','THERMAL_58')),
 company_name text, vat_number text, commercial_registration text, address text, footer_text text,
 show_logo boolean not null default true,
 show_customer_details boolean not null default true,
 show_item_barcode boolean not null default false,
 show_tax_breakdown boolean not null default true,
 updated_at timestamptz not null default now()
);

create table if not exists public.enhar_promotions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 name text not null,
 type text not null check(type in ('PERCENT','FIXED','PRICE')),
 value numeric(14,2) not null check(value>=0),
 starts_on date, ends_on date,
 branch_id uuid,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(company_id,id),
 foreign key(company_id,branch_id) references public.enhar_branches(company_id,id),
 check(ends_on is null or starts_on is null or ends_on>=starts_on)
);

create index if not exists enhar_cash_sessions_company_opened_idx on public.enhar_cash_sessions(company_id,opened_at desc);
create index if not exists enhar_cash_movements_session_idx on public.enhar_cash_movements(company_id,session_id,created_at);
create index if not exists enhar_promotions_company_dates_idx on public.enhar_promotions(company_id,starts_on,ends_on);

do $$
declare t text;
begin
 foreach t in array array['enhar_cashboxes','enhar_cash_sessions','enhar_cash_movements','enhar_cash_settings','enhar_invoice_settings','enhar_promotions'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists %I on public.%I',t||'_member_access',t);
  execute format('create policy %I on public.%I for all to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin()) with check (public.enhar_is_company_member(company_id) or public.is_platform_admin())',t||'_member_access',t);
  execute format('revoke all on public.%I from anon',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 end loop;
end $$;
commit;
