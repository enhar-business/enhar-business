-- ENHAR BUSINESS | Purchase invoice posting
-- Migration 011. Purchase posting updates stock and invoice status in one transaction.
begin;
create or replace function public.enhar_post_purchase_invoice(p_company_id uuid,p_invoice_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare h public.enhar_purchase_invoices%rowtype; l record; v_count integer:=0;
begin
 if auth.uid() is null or not (public.enhar_is_company_admin(p_company_id) or public.is_platform_admin()) then
  raise exception 'Company administrator permission required';
 end if;
 select * into h from public.enhar_purchase_invoices where company_id=p_company_id and id=p_invoice_id for update;
 if not found or h.status<>'DRAFT' then raise exception 'Draft purchase invoice not found'; end if;
 if not exists(select 1 from public.enhar_purchase_invoice_lines where company_id=p_company_id and invoice_id=p_invoice_id) then
  raise exception 'Purchase invoice must contain at least one item';
 end if;
 for l in select * from public.enhar_purchase_invoice_lines where company_id=p_company_id and invoice_id=p_invoice_id loop
  insert into public.enhar_stock_movements(company_id,branch_id,warehouse_id,product_id,movement_type,quantity_in,quantity_out,unit_cost,source_type,source_id,created_by)
  values(p_company_id,h.branch_id,h.warehouse_id,l.product_id,'PURCHASE',l.quantity,0,l.unit_cost,'PURCHASE_INVOICE',h.id,auth.uid());
  v_count:=v_count+1;
 end loop;
 update public.enhar_purchase_invoices set status='POSTED' where company_id=p_company_id and id=p_invoice_id;
 return jsonb_build_object('invoice_id',p_invoice_id,'posted_lines',v_count,'status','POSTED');
end $$;
revoke all on function public.enhar_post_purchase_invoice(uuid,uuid) from public,anon;
grant execute on function public.enhar_post_purchase_invoice(uuid,uuid) to authenticated;
commit;
notify pgrst, 'reload schema';
