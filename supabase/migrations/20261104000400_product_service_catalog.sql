-- ENHAR BUSINESS | Product and service catalog
-- Run after migrations 002 and 003 in Supabase SQL Editor.
begin;

create table if not exists public.enhar_item_categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  category_type text not null check (category_type in ('PRODUCT','SERVICE')),
  name_ar text not null,
  name_en text,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(company_id,id),
  unique(company_id,category_type,name_ar)
);

alter table public.enhar_products
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
  add column if not exists wholesale_price numeric(14,4) not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='enhar_products_company_category_fk') then
    alter table public.enhar_products add constraint enhar_products_company_category_fk
      foreign key(company_id,category_id) references public.enhar_item_categories(company_id,id);
  end if;
  if not exists (select 1 from pg_constraint where conname='enhar_products_company_supplier_fk') then
    alter table public.enhar_products add constraint enhar_products_company_supplier_fk
      foreign key(company_id,default_supplier_id) references public.enhar_suppliers(company_id,id);
  end if;
end $$;

create unique index if not exists enhar_products_company_barcode_uidx
  on public.enhar_products(company_id,barcode) where barcode is not null and barcode <> '';
create index if not exists enhar_item_categories_company_type_idx
  on public.enhar_item_categories(company_id,category_type,is_active);

create table if not exists public.enhar_product_components (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  parent_product_id uuid not null,
  component_product_id uuid not null,
  quantity numeric(14,3) not null check(quantity > 0),
  created_at timestamptz not null default now(),
  foreign key(company_id,parent_product_id) references public.enhar_products(company_id,id) on delete cascade,
  foreign key(company_id,component_product_id) references public.enhar_products(company_id,id),
  check(parent_product_id <> component_product_id),
  unique(company_id,parent_product_id,component_product_id)
);

create table if not exists public.enhar_product_branches (
  company_id uuid not null references public.enhar_companies(id) on delete cascade,
  product_id uuid not null,
  branch_id uuid not null,
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(company_id,product_id,branch_id),
  foreign key(company_id,product_id) references public.enhar_products(company_id,id) on delete cascade,
  foreign key(company_id,branch_id) references public.enhar_branches(company_id,id) on delete cascade
);

alter table public.enhar_item_categories enable row level security;
alter table public.enhar_product_components enable row level security;
alter table public.enhar_product_branches enable row level security;

drop policy if exists enhar_item_categories_member_access on public.enhar_item_categories;
create policy enhar_item_categories_member_access on public.enhar_item_categories
for all to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin())
with check (public.enhar_is_company_member(company_id) or public.is_platform_admin());

drop policy if exists enhar_product_components_member_access on public.enhar_product_components;
create policy enhar_product_components_member_access on public.enhar_product_components
for all to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin())
with check (public.enhar_is_company_member(company_id) or public.is_platform_admin());

drop policy if exists enhar_product_branches_member_access on public.enhar_product_branches;
create policy enhar_product_branches_member_access on public.enhar_product_branches
for all to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin())
with check (public.enhar_is_company_member(company_id) or public.is_platform_admin());

grant select,insert,update,delete on public.enhar_item_categories,public.enhar_product_components,public.enhar_product_branches to authenticated;

commit;
