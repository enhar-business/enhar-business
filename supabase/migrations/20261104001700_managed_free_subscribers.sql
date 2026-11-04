-- Managed free subscriptions and secure platform-created subscriber accounts.
begin;

insert into public.enhar_subscription_plans
(plan_code,name_ar,name_en,billing_period,amount_halalas,currency,is_test,is_active,cashbox_limit,user_limit)
values
('FREE-MANAGED','مجانية بإدارة المنصة','Platform-managed free','TEST',0,'SAR',false,true,100,500)
on conflict(plan_code) do update set
 name_ar=excluded.name_ar,name_en=excluded.name_en,billing_period='TEST',
 amount_halalas=0,currency='SAR',is_test=false,is_active=true,
 cashbox_limit=100,user_limit=500;

create or replace function public.enhar_admin_create_managed_company(
 p_owner_user_id uuid,
 p_name_ar text,
 p_name_en text default null,
 p_period_end timestamptz default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_company uuid; v_branch uuid; v_code text; v_end timestamptz;
 v_plan public.enhar_subscription_plans%rowtype;
 v_owner_name text;
begin
 if auth.role() <> 'service_role' then raise exception 'Service role required'; end if;
 if p_owner_user_id is null then raise exception 'Owner user is required'; end if;
 if p_name_ar is null or char_length(trim(p_name_ar))<2 or char_length(trim(p_name_ar))>200 then raise exception 'Company name must be between 2 and 200 characters'; end if;
 if not exists(select 1 from auth.users where id=p_owner_user_id) then raise exception 'Owner auth user not found'; end if;
 select * into v_plan from public.enhar_subscription_plans where plan_code='FREE-MANAGED' and is_active and not is_test;
 if not found then raise exception 'Free plan is not configured'; end if;
 v_end:=coalesce(p_period_end,now()+interval '1 year');
 if v_end<=now() then raise exception 'Subscription end date must be in the future'; end if;
 v_code:='ENH-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 insert into public.enhar_companies(company_code,name_ar,name_en,created_by,status,subscription_status,trial_started_at,trial_ends_at)
 values(v_code,trim(p_name_ar),nullif(trim(coalesce(p_name_en,'')),''),p_owner_user_id,'ACTIVE','ACTIVE',now(),v_end)
 returning id into v_company;
 insert into public.enhar_company_memberships(company_id,user_id,role,status)
 values(v_company,p_owner_user_id,'OWNER','ACTIVE');
 insert into public.enhar_branches(company_id,branch_code,name_ar,name_en)
 values(v_company,'MAIN','الفرع الرئيسي','Main Branch') returning id into v_branch;
 insert into public.enhar_warehouses(company_id,branch_id,warehouse_code,name_ar,name_en)
 values(v_company,v_branch,'MAIN','المستودع الرئيسي','Main Warehouse');
 select raw_user_meta_data->>'full_name' into v_owner_name from auth.users where id=p_owner_user_id;
 insert into public.enhar_profiles(user_id,full_name,phone)
 values(p_owner_user_id,nullif(v_owner_name,''),null)
 on conflict(user_id) do update set full_name=coalesce(public.enhar_profiles.full_name,excluded.full_name);
 insert into public.enhar_company_subscriptions(company_id,plan_id,status,current_period_start,current_period_end,extra_cashboxes,extra_users,updated_at)
 values(v_company,v_plan.id,'ACTIVE',now(),v_end,0,0,now())
 on conflict(company_id) do update set plan_id=excluded.plan_id,status='ACTIVE',current_period_start=now(),current_period_end=excluded.current_period_end,updated_at=now();
 return jsonb_build_object('company_id',v_company,'company_code',v_code,'owner_user_id',p_owner_user_id,'plan_code','FREE-MANAGED','subscription_status','ACTIVE','period_end',v_end);
end $$;

revoke all on function public.enhar_admin_create_managed_company(uuid,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.enhar_admin_create_managed_company(uuid,text,text,timestamptz) to service_role;


create or replace function public.enhar_admin_manage_free_subscription(
 p_company_id uuid,
 p_action text,
 p_period_end timestamptz default null
) returns jsonb
language plpgsql security definer set search_path=''
as $free_subscription$
declare v_company public.enhar_companies%rowtype; v_plan public.enhar_subscription_plans%rowtype;
begin
 if auth.uid() is null or not public.is_platform_admin() then raise exception 'Platform administrator required'; end if;
 select * into v_company from public.enhar_companies where id=p_company_id for update;
 if not found then raise exception 'Company not found'; end if;
 if p_action in ('RENEW','ACTIVATE') then
   select * into v_plan from public.enhar_subscription_plans where plan_code='FREE-MANAGED' and is_active and not is_test;
   if not found then raise exception 'Free plan is not configured'; end if;
   if p_action='RENEW' and (p_period_end is null or p_period_end<=now()) then raise exception 'A future end date is required'; end if;
   insert into public.enhar_company_subscriptions(company_id,plan_id,status,current_period_start,current_period_end,extra_cashboxes,extra_users,updated_at)
   values(p_company_id,v_plan.id,'ACTIVE',now(),coalesce(p_period_end,now()+interval '1 year'),0,0,now())
   on conflict(company_id) do update set plan_id=excluded.plan_id,status='ACTIVE',current_period_start=now(),current_period_end=excluded.current_period_end,updated_at=now();
   update public.enhar_companies set status='ACTIVE',subscription_status='ACTIVE',trial_ends_at=coalesce(p_period_end,now()+interval '1 year'),updated_at=now() where id=p_company_id;
 elsif p_action='SUSPEND' then
   update public.enhar_companies set status='SUSPENDED',subscription_status='SUSPENDED',updated_at=now() where id=p_company_id;
   update public.enhar_company_subscriptions set status='SUSPENDED',updated_at=now() where company_id=p_company_id;
 elsif p_action='CLOSE' then
   update public.enhar_companies set status='CLOSED',subscription_status='CANCELLED',updated_at=now() where id=p_company_id;
   update public.enhar_company_subscriptions set status='CANCELLED',updated_at=now() where company_id=p_company_id;
 else raise exception 'Unsupported free subscription action'; end if;
 insert into public.enhar_subscription_audit(company_id,actor_user_id,action,details)
 values(p_company_id,auth.uid(),'FREE_'||p_action,jsonb_build_object('period_end',p_period_end));
 return jsonb_build_object('ok',true,'action',p_action,'company_id',p_company_id);
end $free_subscription$;
revoke all on function public.enhar_admin_manage_free_subscription(uuid,text,timestamptz) from public,anon;
grant execute on function public.enhar_admin_manage_free_subscription(uuid,text,timestamptz) to authenticated;

commit;
