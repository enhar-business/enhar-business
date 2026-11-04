-- ENHAR BUSINESS | POS customer wallet redemption
-- Migration 012. Calls the existing atomic POS posting routine and records wallet redemption
-- in the same database transaction. Existing six-argument POS RPC remains compatible.
begin;

do $$
declare c record;
begin
 for c in
  select conname from pg_constraint
  where conrelid='public.enhar_sales_payments'::regclass and contype='c'
    and pg_get_constraintdef(oid) ilike '%payment_method%'
 loop
  execute format('alter table public.enhar_sales_payments drop constraint %I',c.conname);
 end loop;
end $$;
alter table public.enhar_sales_payments
 add constraint enhar_sales_payments_method_check
 check(payment_method in ('CASH','CARD','BANK_TRANSFER','WALLET'));

alter table public.enhar_sales_invoices add column if not exists seller_staff_id uuid;
do $
begin
 if not exists(select 1 from pg_constraint where conname='enhar_sales_invoice_seller_staff_fk') then
  alter table public.enhar_sales_invoices
   add constraint enhar_sales_invoice_seller_staff_fk
   foreign key(company_id,seller_staff_id) references public.enhar_staff(company_id,id);
 end if;
end $;

create or replace function public.enhar_post_pos_invoice_with_wallet(
 p_company_id uuid,p_branch_id uuid,p_cash_session_id uuid,p_customer_id uuid,
 p_payment_method text,p_lines jsonb,p_wallet_amount numeric default 0,p_seller_staff_id uuid default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_result jsonb; v_invoice_id uuid; v_total numeric(14,2); v_wallet_id uuid;
 v_balance numeric(14,2); v_wallet_amount numeric(14,2):=coalesce(p_wallet_amount,0);
 v_cash_part numeric(14,2); v_tx uuid;
begin
 if auth.uid() is null or not public.enhar_is_company_member(p_company_id) then
  raise exception 'Company membership required';
 end if;
 if v_wallet_amount<0 then raise exception 'Wallet amount cannot be negative'; end if;
 if p_seller_staff_id is not null and not exists(select 1 from public.enhar_staff s where s.company_id=p_company_id and s.id=p_seller_staff_id and s.is_active and s.show_in_pos) then raise exception 'Selected seller is not available in POS'; end if;
 if v_wallet_amount>0 and p_customer_id is null then raise exception 'Select a customer before using wallet balance'; end if;

 -- Use CARD as a temporary non-cash method so the legacy routine does not overstate cash receipts.
 v_result:=public.enhar_post_pos_invoice(
  p_company_id,p_branch_id,p_cash_session_id,p_customer_id,
  case when v_wallet_amount>0 then 'CARD' else p_payment_method end,p_lines
 );
 if p_seller_staff_id is not null then update public.enhar_sales_invoices set seller_staff_id=p_seller_staff_id where company_id=p_company_id and id=(v_result->>'invoice_id')::uuid; end if;
 if v_wallet_amount=0 then return v_result; end if;

 v_invoice_id:=(v_result->>'invoice_id')::uuid;
 v_total:=(v_result->>'grand_total')::numeric;
 if v_wallet_amount>v_total then raise exception 'Wallet redemption exceeds invoice total'; end if;
 insert into public.enhar_customer_wallets(company_id,customer_id,balance)
 values(p_company_id,p_customer_id,0)
 on conflict(company_id,customer_id) do nothing;
 select id,balance into v_wallet_id,v_balance
 from public.enhar_customer_wallets
 where company_id=p_company_id and customer_id=p_customer_id
 for update;
 if v_balance<v_wallet_amount then raise exception 'رصيد العميل غير كافٍ. المتاح: %',v_balance; end if;

 update public.enhar_customer_wallets
 set balance=balance-v_wallet_amount,updated_at=now()
 where company_id=p_company_id and id=v_wallet_id;

 insert into public.enhar_customer_wallet_transactions
 (company_id,wallet_id,customer_id,transaction_type,amount,balance_after,payment_method,reference_type,reference_id,notes,created_by)
 values(p_company_id,v_wallet_id,p_customer_id,'REDEEM',v_wallet_amount,(v_balance-v_wallet_amount), 'WALLET','SALES_INVOICE',v_invoice_id,'استخدام رصيد في فاتورة بيع',auth.uid())
 returning id into v_tx;

 delete from public.enhar_sales_payments
 where company_id=p_company_id and invoice_id=v_invoice_id;

 v_cash_part:=round(v_total-v_wallet_amount,2);
 if v_cash_part>0 then
  insert into public.enhar_sales_payments(company_id,invoice_id,payment_method,amount,reference,created_by)
  values(p_company_id,v_invoice_id,p_payment_method,v_cash_part,'تحصيل متبقٍ بعد استخدام رصيد العميل',auth.uid());
  if p_payment_method='CASH' then
   insert into public.enhar_cash_movements(company_id,session_id,movement_type,payment_method,amount,reference,notes,created_by)
   values(p_company_id,p_cash_session_id,'SALE','CASH',v_cash_part,v_result->>'invoice_number','تحصيل الجزء النقدي بعد استخدام رصيد العميل',auth.uid());
   update public.enhar_cash_sessions
   set expected_amount=coalesce(expected_amount,opening_amount)+v_cash_part
   where company_id=p_company_id and id=p_cash_session_id and status='OPEN';
  end if;
 end if;
 insert into public.enhar_sales_payments(company_id,invoice_id,payment_method,amount,reference,created_by)
 values(p_company_id,v_invoice_id,'WALLET',v_wallet_amount,'رصيد العميل',auth.uid());

 return v_result||jsonb_build_object('wallet_used',v_wallet_amount,'wallet_balance_after',v_balance-v_wallet_amount,'cash_due',v_cash_part,'wallet_transaction_id',v_tx);
end $$;

revoke all on function public.enhar_post_pos_invoice_with_wallet(uuid,uuid,uuid,uuid,text,jsonb,numeric,uuid) from public,anon;
grant execute on function public.enhar_post_pos_invoice_with_wallet(uuid,uuid,uuid,uuid,text,jsonb,numeric,uuid) to authenticated;
commit;
notify pgrst, 'reload schema';
