-- ENHAR BUSINESS | Controlled appointment and stock posting workflows
-- Migration 010. Additive; never edits or deletes historical movement rows.
begin;

create or replace function public.enhar_create_appointment(
 p_company_id uuid,p_branch_id uuid,p_customer_id uuid,p_service_product_id uuid,
 p_staff_id uuid,p_starts_at timestamptz,p_ends_at timestamptz,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_number text;
begin
 if auth.uid() is null or not public.enhar_is_company_member(p_company_id) then
  raise exception 'Company membership required';
 end if;
 if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at then
  raise exception 'Appointment time range is invalid';
 end if;
 if not exists(select 1 from public.enhar_branches b where b.company_id=p_company_id and b.id=p_branch_id and b.is_active) then
  raise exception 'Invalid branch';
 end if;
 if p_customer_id is not null and not exists(select 1 from public.enhar_customers c where c.company_id=p_company_id and c.id=p_customer_id and c.is_active) then
  raise exception 'Invalid customer';
 end if;
 if not exists(select 1 from public.enhar_products p where p.company_id=p_company_id and p.id=p_service_product_id and p.item_type='SERVICE' and p.is_active) then
  raise exception 'Select an active service';
 end if;
 if not exists(select 1 from public.enhar_staff s where s.company_id=p_company_id and s.id=p_staff_id and s.is_active and s.can_perform_services) then
  raise exception 'Selected employee is not an active service provider';
 end if;

 perform pg_advisory_xact_lock(hashtextextended(p_company_id::text||p_staff_id::text,0));
 if exists(
  select 1 from public.enhar_appointments a
  where a.company_id=p_company_id and a.staff_id=p_staff_id
    and a.status not in ('CANCELLED','NO_SHOW')
    and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)')
 ) then raise exception 'الموظف لديه حجز آخر في هذا الوقت'; end if;

 v_number:='APT-'||to_char((p_starts_at at time zone 'Asia/Riyadh'),'YYYYMMDD-HH24MI')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
 insert into public.enhar_appointments(company_id,branch_id,customer_id,service_product_id,staff_id,appointment_number,starts_at,ends_at,status,notes,created_by)
 values(p_company_id,p_branch_id,p_customer_id,p_service_product_id,p_staff_id,v_number,p_starts_at,p_ends_at,'BOOKED',p_notes,auth.uid())
 returning id into v_id;
 return v_id;
end $$;

create or replace function public.enhar_post_stock_document(p_company_id uuid,p_document_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare d public.enhar_stock_documents%rowtype; l record; v_count integer:=0; v_in numeric:=0; v_out numeric:=0;
begin
 if auth.uid() is null or not (public.enhar_is_company_admin(p_company_id) or public.is_platform_admin()) then
  raise exception 'Company administrator permission required';
 end if;
 select * into d from public.enhar_stock_documents
 where company_id=p_company_id and id=p_document_id for update;
 if not found or d.status<>'DRAFT' then raise exception 'Draft stock document not found'; end if;
 if not exists(select 1 from public.enhar_stock_document_lines where company_id=p_company_id and document_id=p_document_id) then
  raise exception 'Stock document must contain at least one item';
 end if;
 for l in select * from public.enhar_stock_document_lines where company_id=p_company_id and document_id=p_document_id loop
  if d.document_type in ('RECEIPT','SALES_RETURN') then
   v_in:=l.quantity;v_out:=0;
   insert into public.enhar_stock_movements(company_id,branch_id,warehouse_id,product_id,movement_type,quantity_in,quantity_out,unit_cost,source_type,source_id,created_by)
   values(p_company_id,d.branch_id,d.warehouse_id,l.product_id,case when d.document_type='SALES_RETURN' then 'SALES_RETURN' else 'PURCHASE' end,v_in,0,l.unit_cost,'STOCK_DOCUMENT',d.id,auth.uid());
  elsif d.document_type in ('ISSUE','PURCHASE_RETURN') then
   select coalesce(sum(quantity_in-quantity_out),0) into v_in
   from public.enhar_stock_movements where company_id=p_company_id and warehouse_id=d.warehouse_id and product_id=l.product_id;
   if v_in<l.quantity then raise exception 'المخزون غير كافٍ للصنف %',l.product_id; end if;
   insert into public.enhar_stock_movements(company_id,branch_id,warehouse_id,product_id,movement_type,quantity_in,quantity_out,unit_cost,source_type,source_id,created_by)
   values(p_company_id,d.branch_id,d.warehouse_id,l.product_id,case when d.document_type='PURCHASE_RETURN' then 'PURCHASE_RETURN' else 'ADJUSTMENT' end,0,l.quantity,l.unit_cost,'STOCK_DOCUMENT',d.id,auth.uid());
  elsif d.document_type='TRANSFER' then
   select coalesce(sum(quantity_in-quantity_out),0) into v_in
   from public.enhar_stock_movements where company_id=p_company_id and warehouse_id=d.warehouse_id and product_id=l.product_id;
   if v_in<l.quantity then raise exception 'المخزون غير كافٍ للتحويل للصنف %',l.product_id; end if;
   insert into public.enhar_stock_movements(company_id,branch_id,warehouse_id,product_id,movement_type,quantity_in,quantity_out,unit_cost,source_type,source_id,created_by)
   values(p_company_id,d.branch_id,d.warehouse_id,l.product_id,'TRANSFER_OUT',0,l.quantity,l.unit_cost,'STOCK_DOCUMENT',d.id,auth.uid());
   insert into public.enhar_stock_movements(company_id,branch_id,warehouse_id,product_id,movement_type,quantity_in,quantity_out,unit_cost,source_type,source_id,created_by)
   values(p_company_id,d.branch_id,d.destination_warehouse_id,l.product_id,'TRANSFER_IN',l.quantity,0,l.unit_cost,'STOCK_DOCUMENT',d.id,auth.uid());
  else
   raise exception 'Unsupported document type';
  end if;
  v_count:=v_count+1;
 end loop;
 update public.enhar_stock_documents set status='POSTED',posted_by=auth.uid(),posted_at=now()
 where company_id=p_company_id and id=p_document_id;
 return jsonb_build_object('document_id',p_document_id,'posted_lines',v_count,'status','POSTED');
end $$;

create or replace function public.enhar_approve_stock_count(p_company_id uuid,p_count_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare c public.enhar_stock_counts%rowtype; l record; v_diff numeric(14,3); v_cost numeric(14,4); v_lines integer:=0;
begin
 if auth.uid() is null or not (public.enhar_is_company_admin(p_company_id) or public.is_platform_admin()) then
  raise exception 'Company administrator permission required';
 end if;
 select * into c from public.enhar_stock_counts where company_id=p_company_id and id=p_count_id for update;
 if not found or c.status not in ('DRAFT','IN_PROGRESS','SUBMITTED') then raise exception 'Stock count cannot be approved'; end if;
 if exists(select 1 from public.enhar_stock_count_lines where company_id=p_company_id and stock_count_id=p_count_id and counted_quantity is null) then
  raise exception 'Enter counted quantity for every stock item first';
 end if;
 for l in select * from public.enhar_stock_count_lines where company_id=p_company_id and stock_count_id=p_count_id loop
  v_diff:=l.counted_quantity-l.system_quantity;
  if v_diff<>0 then
   select purchase_price into v_cost from public.enhar_products where company_id=p_company_id and id=l.product_id;
   insert into public.enhar_stock_movements(company_id,branch_id,warehouse_id,product_id,movement_type,quantity_in,quantity_out,unit_cost,source_type,source_id,created_by)
   values(p_company_id,c.branch_id,c.warehouse_id,l.product_id,'ADJUSTMENT',greatest(v_diff,0),greatest(-v_diff,0),coalesce(v_cost,0),'STOCK_COUNT',c.id,auth.uid());
  end if;
  v_lines:=v_lines+1;
 end loop;
 update public.enhar_stock_counts set status='APPROVED',approved_by=auth.uid(),approved_at=now()
 where company_id=p_company_id and id=p_count_id;
 return jsonb_build_object('count_id',p_count_id,'counted_lines',v_lines,'status','APPROVED');
end $$;

revoke all on function public.enhar_create_appointment(uuid,uuid,uuid,uuid,uuid,timestamptz,timestamptz,text) from public,anon;
revoke all on function public.enhar_post_stock_document(uuid,uuid) from public,anon;
revoke all on function public.enhar_approve_stock_count(uuid,uuid) from public,anon;
grant execute on function public.enhar_create_appointment(uuid,uuid,uuid,uuid,uuid,timestamptz,timestamptz,text) to authenticated;
grant execute on function public.enhar_post_stock_document(uuid,uuid) to authenticated;
grant execute on function public.enhar_approve_stock_count(uuid,uuid) to authenticated;

commit;
notify pgrst, 'reload schema';
