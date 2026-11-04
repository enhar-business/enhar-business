-- ENHAR BUSINESS | Platform company provisioning and customer wallet RPCs
-- Migration 009. Additive and safe to re-run. Run after migration 007/008.
begin;

create or replace function public.enhar_admin_create_company(
  p_name_ar text,
  p_owner_email text,
  p_name_en text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_company_id uuid;
  v_branch_id uuid;
  v_code text;
  v_email text := lower(trim(coalesce(p_owner_email,'')));
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'Platform administrator permission required';
  end if;
  if char_length(trim(coalesce(p_name_ar,''))) < 2 then
    raise exception 'Company Arabic name is required';
  end if;
  if v_email = '' then
    raise exception 'Owner email is required';
  end if;

  select u.id into v_owner_id
  from auth.users u
  where lower(u.email) = v_email
  limit 1;

  if v_owner_id is null then
    raise exception 'لا يوجد حساب مسجل بهذا البريد. يجب على مالك الشركة إنشاء حساب أولاً.';
  end if;

  v_code := 'ENH-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));

  insert into public.enhar_companies
    (company_code,name_ar,name_en,created_by,trial_started_at,trial_ends_at,status,subscription_status)
  values
    (v_code,trim(p_name_ar),nullif(trim(coalesce(p_name_en,'')),''),auth.uid(),now(),now()+interval '15 days','ACTIVE','TRIAL')
  returning id into v_company_id;

  insert into public.enhar_company_memberships(company_id,user_id,role,status)
  values(v_company_id,v_owner_id,'OWNER','ACTIVE');

  insert into public.enhar_branches(company_id,branch_code,name_ar,name_en)
  values(v_company_id,'MAIN','الفرع الرئيسي','Main Branch')
  returning id into v_branch_id;

  insert into public.enhar_warehouses(company_id,branch_id,warehouse_code,name_ar,name_en)
  values(v_company_id,v_branch_id,'MAIN','المستودع الرئيسي','Main Warehouse');

  return jsonb_build_object(
    'company_id',v_company_id,
    'company_code',v_code,
    'owner_user_id',v_owner_id,
    'trial_days',15,
    'trial_ends_at',now()+interval '15 days'
  );
end;
$$;

revoke all on function public.enhar_admin_create_company(text,text,text) from public,anon;
grant execute on function public.enhar_admin_create_company(text,text,text) to authenticated;

create or replace function public.enhar_customer_wallet_post(
  p_company_id uuid,
  p_customer_id uuid,
  p_transaction_type text,
  p_amount numeric,
  p_payment_method text default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wallet_id uuid;
  v_balance numeric(14,2);
  v_after numeric(14,2);
  v_tx uuid;
  v_type text := upper(trim(coalesce(p_transaction_type,'')));
begin
  if auth.uid() is null or not (
    public.enhar_is_company_admin(p_company_id) or public.is_platform_admin()
  ) then
    raise exception 'Company administrator permission required';
  end if;
  if v_type not in ('DEPOSIT','REDEEM','REFUND','ADJUSTMENT') then
    raise exception 'Unsupported wallet transaction type';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;
  if not exists (
    select 1 from public.enhar_customers c
    where c.company_id=p_company_id and c.id=p_customer_id and c.is_active
  ) then
    raise exception 'Customer not found or inactive';
  end if;

  insert into public.enhar_customer_wallets(company_id,customer_id,balance)
  values(p_company_id,p_customer_id,0)
  on conflict(company_id,customer_id) do nothing;

  select id,balance into v_wallet_id,v_balance
  from public.enhar_customer_wallets
  where company_id=p_company_id and customer_id=p_customer_id
  for update;

  if v_type='REDEEM' then
    if v_balance < p_amount then
      raise exception 'رصيد العميل غير كافٍ. المتاح: %',v_balance;
    end if;
    v_after:=v_balance-p_amount;
  else
    v_after:=v_balance+p_amount;
  end if;

  update public.enhar_customer_wallets
  set balance=v_after,updated_at=now()
  where company_id=p_company_id and id=v_wallet_id;

  insert into public.enhar_customer_wallet_transactions
    (company_id,wallet_id,customer_id,transaction_type,amount,balance_after,
     payment_method,reference_type,notes,created_by)
  values
    (p_company_id,v_wallet_id,p_customer_id,v_type,p_amount,v_after,
     p_payment_method,'MANUAL',p_notes,auth.uid())
  returning id into v_tx;

  return jsonb_build_object('transaction_id',v_tx,'balance',v_after);
end;
$$;
revoke all on function public.enhar_customer_wallet_post(uuid,uuid,text,numeric,text,text) from public,anon;
grant execute on function public.enhar_customer_wallet_post(uuid,uuid,text,numeric,text,text) to authenticated;

commit;

notify pgrst, 'reload schema';
