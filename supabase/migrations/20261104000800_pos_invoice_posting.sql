-- ENHAR BUSINESS | Atomic POS invoice posting
begin;

create table if not exists public.enhar_sales_payments (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.enhar_companies(id) on delete cascade,
 invoice_id uuid not null,
 payment_method text not null check(payment_method in ('CASH','CARD','BANK_TRANSFER')),
 amount numeric(14,2) not null check(amount>0),
 reference text,
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 foreign key(company_id,invoice_id) references public.enhar_sales_invoices(company_id,id) on delete cascade
);
alter table public.enhar_sales_payments enable row level security;
drop policy if exists enhar_sales_payments_member_access on public.enhar_sales_payments;
create policy enhar_sales_payments_member_access on public.enhar_sales_payments
 for all to authenticated
 using(public.enhar_is_company_member(company_id) or public.is_platform_admin())
 with check(public.enhar_is_company_member(company_id) or public.is_platform_admin());
grant select on public.enhar_sales_payments to authenticated;
revoke insert,update,delete on public.enhar_sales_payments from authenticated;

create or replace function public.enhar_post_pos_invoice(
 p_company_id uuid,
 p_branch_id uuid,
 p_cash_session_id uuid,
 p_customer_id uuid,
 p_payment_method text,
 p_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 v_warehouse_id uuid;
 v_invoice_id uuid;
 v_invoice_number text;
 v_session public.enhar_cash_sessions%rowtype;
 v_line jsonb;
 v_product public.enhar_products%rowtype;
 v_qty numeric(14,3);
 v_price numeric(14,4);
 v_discount numeric(14,2);
 v_base numeric(14,2);
 v_tax numeric(14,2);
 v_subtotal numeric(14,2):=0;
 v_tax_total numeric(14,2):=0;
 v_grand numeric(14,2):=0;
 v_stock numeric(14,3);
 v_cash numeric(14,2):=0;
begin
 if auth.uid() is null or not public.enhar_is_company_member(p_company_id) then
  raise exception 'يجب تسجيل الدخول بعضوية فعالة في المنشأة';
 end if;
 if p_payment_method not in ('CASH','CARD','BANK_TRANSFER') then
  raise exception 'طريقة الدفع غير مدعومة';
 end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
  raise exception 'أضف صنفاً واحداً على الأقل';
 end if;
 select id into v_warehouse_id from public.enhar_warehouses
 where company_id=p_company_id and branch_id=p_branch_id and is_active
 order by created_at limit 1;
 if v_warehouse_id is null then raise exception 'لا يوجد مستودع نشط لهذا الفرع'; end if;
 select * into v_session from public.enhar_cash_sessions
 where company_id=p_company_id and id=p_cash_session_id and branch_id=p_branch_id and status='OPEN'
 for update;
 if not found then raise exception 'اختر جلسة صندوق مفتوحة لهذا الفرع'; end if;
 if p_customer_id is not null and not exists(
  select 1 from public.enhar_customers where company_id=p_company_id and id=p_customer_id and is_active
 ) then raise exception 'العميل المحدد غير صالح'; end if;

 -- Validate every line and calculate authoritative tax and totals from the catalog.
 for v_line in select value from jsonb_array_elements(p_lines) loop
  select * into v_product from public.enhar_products
  where company_id=p_company_id and id=(v_line->>'product_id')::uuid and is_active and show_in_pos
  for share;
  if not found then raise exception 'أحد الأصناف غير موجود أو غير متاح للبيع'; end if;
  v_qty:=nullif(v_line->>'quantity','')::numeric;
  v_price:=nullif(v_line->>'unit_price','')::numeric;
  v_discount:=coalesce(nullif(v_line->>'discount','')::numeric,0);
  if v_qty is null or v_qty<=0 or v_price is null or v_price<0 or v_discount<0 then
   raise exception 'الكمية أو السعر أو الخصم غير صالح';
  end if;
  v_base:=round(v_qty*v_price-v_discount,2);
  if v_base<0 then raise exception 'الخصم أكبر من قيمة السطر'; end if;
  v_tax:=round(v_base*v_product.tax_rate/100,2);
  v_subtotal:=v_subtotal+v_base;
  v_tax_total:=v_tax_total+v_tax;
  if v_product.item_type='PRODUCT' then
   select coalesce(sum(quantity_in-quantity_out),0) into v_stock
   from public.enhar_stock_movements
   where company_id=p_company_id and warehouse_id=v_warehouse_id and product_id=v_product.id;
   if v_stock<v_qty then raise exception 'المخزون غير كافٍ للصنف: % (المتاح %)',v_product.name_ar,v_stock; end if;
  end if;
 end loop;
 v_grand:=round(v_subtotal+v_tax_total,2);
 v_invoice_number:='POS-'||to_char((now() at time zone 'Asia/Riyadh'),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into public.enhar_sales_invoices(company_id,branch_id,warehouse_id,customer_id,invoice_number,invoice_date,status,subtotal,tax_total,grand_total,created_by)
 values(p_company_id,p_branch_id,v_warehouse_id,p_customer_id,v_invoice_number,(now() at time zone 'Asia/Riyadh')::date,'POSTED',v_subtotal,v_tax_total,v_grand,auth.uid())
 returning id into v_invoice_id;

 for v_line in select value from jsonb_array_elements(p_lines) loop
  select * into v_product from public.enhar_products
  where company_id=p_company_id and id=(v_line->>'product_id')::uuid;
  v_qty:=(v_line->>'quantity')::numeric;
  v_price:=(v_line->>'unit_price')::numeric;
  v_discount:=coalesce(nullif(v_line->>'discount','')::numeric,0);
  v_base:=round(v_qty*v_price-v_discount,2);
  v_tax:=round(v_base*v_product.tax_rate/100,2);
  insert into public.enhar_sales_invoice_lines(company_id,invoice_id,product_id,description,quantity,unit_price,discount,tax_rate,line_total)
  values(p_company_id,v_invoice_id,v_product.id,v_product.name_ar,v_qty,v_price,v_discount,v_product.tax_rate,round(v_base+v_tax,2));
  if v_product.item_type='PRODUCT' then
   insert into public.enhar_stock_movements(company_id,branch_id,warehouse_id,product_id,movement_type,quantity_out,unit_cost,source_type,source_id,created_by)
   values(p_company_id,p_branch_id,v_warehouse_id,v_product.id,'SALE',v_qty,v_product.purchase_price,'SALES_INVOICE',v_invoice_id,auth.uid());
  end if;
 end loop;
 insert into public.enhar_sales_payments(company_id,invoice_id,payment_method,amount,created_by)
 values(p_company_id,v_invoice_id,p_payment_method,v_grand,auth.uid());
 if p_payment_method='CASH' then
  insert into public.enhar_cash_movements(company_id,session_id,movement_type,payment_method,amount,reference,notes,created_by)
  values(p_company_id,p_cash_session_id,'SALE','CASH',v_grand,v_invoice_number,'تحصيل فاتورة نقطة بيع',auth.uid());
  update public.enhar_cash_sessions set expected_amount=coalesce(expected_amount,opening_amount)+v_grand
  where company_id=p_company_id and id=p_cash_session_id;
 end if;
 return jsonb_build_object('invoice_id',v_invoice_id,'invoice_number',v_invoice_number,'subtotal',v_subtotal,'tax_total',v_tax_total,'grand_total',v_grand,'status','POSTED');
end $$;

revoke all on function public.enhar_post_pos_invoice(uuid,uuid,uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.enhar_post_pos_invoice(uuid,uuid,uuid,uuid,text,jsonb) to authenticated;
commit;
