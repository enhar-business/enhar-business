-- ENHAR BUSINESS subscription catalog, add-ons, quotas and platform controls
begin;

alter table public.enhar_subscription_plans
  drop constraint if exists enhar_subscription_plans_billing_period_check;
alter table public.enhar_subscription_plans
  add constraint enhar_subscription_plans_billing_period_check
  check (billing_period in ('SIX_MONTHS','YEARLY','TEST'));

alter table public.enhar_subscription_plans
  add column if not exists cashbox_limit integer not null default 2 check(cashbox_limit>=0),
  add column if not exists user_limit integer not null default 9 check(user_limit>=1);

alter table public.enhar_company_subscriptions
  add column if not exists extra_cashboxes integer not null default 0 check(extra_cashboxes>=0),
  add column if not exists extra_users integer not null default 0 check(extra_users>=0);

alter table public.enhar_subscription_orders
  add column if not exists order_type text not null default 'PLAN' check(order_type in ('PLAN','ADDON_CASHBOX','ADDON_USER')),
  add column if not exists quantity integer not null default 1 check(quantity>=1),
  add column if not exists duration_months integer not null default 6 check(duration_months in (6,12));

create table if not exists public.enhar_subscription_audit (
 id uuid primary key default gen_random_uuid(),
 company_id uuid references public.enhar_companies(id) on delete set null,
 actor_user_id uuid references auth.users(id) on delete set null,
 action text not null,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
alter table public.enhar_subscription_audit enable row level security;
drop policy if exists enhar_subscription_audit_platform_read on public.enhar_subscription_audit;
create policy enhar_subscription_audit_platform_read on public.enhar_subscription_audit
for select to authenticated using(public.is_platform_admin());

insert into public.enhar_subscription_plans
(plan_code,name_ar,name_en,billing_period,amount_halalas,currency,is_test,is_active,cashbox_limit,user_limit)
values
('BASIC-6M','الباقة الأساسية - 6 أشهر','Basic - 6 months','SIX_MONTHS',100000,'SAR',false,true,2,9),
('BASIC-12M','الباقة الأساسية - سنة','Basic - 12 months','YEARLY',180000,'SAR',false,true,2,9),
('MEDIUM-6M','الباقة المتوسطة - 6 أشهر','Medium - 6 months','SIX_MONTHS',150000,'SAR',false,true,4,18),
('MEDIUM-12M','الباقة المتوسطة - سنة','Medium - 12 months','YEARLY',280000,'SAR',false,true,4,18),
('PREMIUM-6M','الباقة الأعلى - 6 أشهر','Premium - 6 months','SIX_MONTHS',200000,'SAR',false,true,6,27),
('PREMIUM-12M','الباقة الأعلى - سنة','Premium - 12 months','YEARLY',380000,'SAR',false,true,6,27)
on conflict(plan_code) do update set
 name_ar=excluded.name_ar,name_en=excluded.name_en,billing_period=excluded.billing_period,
 amount_halalas=excluded.amount_halalas,currency=excluded.currency,is_test=false,is_active=true,
 cashbox_limit=excluded.cashbox_limit,user_limit=excluded.user_limit;

create or replace function public.enhar_admin_manage_subscription(
 p_company_id uuid,
 p_action text,
 p_plan_code text default null,
 p_status text default null,
 p_extra_cashboxes integer default null,
 p_extra_users integer default null,
 p_period_end timestamptz default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_plan public.enhar_subscription_plans%rowtype; v_sub public.enhar_company_subscriptions%rowtype;
begin
 if auth.uid() is null or not public.is_platform_admin() then raise exception 'Platform administrator required'; end if;
 if p_action='SET_PLAN' then
  select * into v_plan from public.enhar_subscription_plans where plan_code=p_plan_code and is_active and not is_test;
  if not found then raise exception 'Invalid plan'; end if;
  insert into public.enhar_company_subscriptions(company_id,plan_id,status,current_period_start,current_period_end,updated_at)
  values(p_company_id,v_plan.id,'ACTIVE',now(),coalesce(p_period_end,now()+case when v_plan.billing_period='YEARLY' then interval '1 year' else interval '6 months' end),now())
  on conflict(company_id) do update set plan_id=excluded.plan_id,status='ACTIVE',current_period_start=now(),current_period_end=excluded.current_period_end,updated_at=now();
  update public.enhar_companies set status='ACTIVE',subscription_status='ACTIVE',updated_at=now() where id=p_company_id;
 elsif p_action='SET_STATUS' then
  if p_status not in ('ACTIVE','PAST_DUE','CANCELLED','EXPIRED','SUSPENDED') then raise exception 'Invalid subscription status'; end if;
  update public.enhar_company_subscriptions set status=p_status,updated_at=now() where company_id=p_company_id;
  update public.enhar_companies set subscription_status=case when p_status='ACTIVE' then 'ACTIVE' when p_status='SUSPENDED' then 'SUSPENDED' when p_status='CANCELLED' then 'CANCELLED' else 'PAST_DUE' end,
    status=case when p_status='SUSPENDED' then 'SUSPENDED' else 'ACTIVE' end,updated_at=now() where id=p_company_id;
 elsif p_action='SET_ADDONS' then
  if coalesce(p_extra_cashboxes,-1)<0 or coalesce(p_extra_users,-1)<0 then raise exception 'Add-on quantities must be zero or greater'; end if;
  update public.enhar_company_subscriptions set extra_cashboxes=p_extra_cashboxes,extra_users=p_extra_users,updated_at=now() where company_id=p_company_id;
  if not found then raise exception 'Subscription not found'; end if;
 else raise exception 'Unsupported action'; end if;
 insert into public.enhar_subscription_audit(company_id,actor_user_id,action,details)
 values(p_company_id,auth.uid(),p_action,jsonb_build_object('plan_code',p_plan_code,'status',p_status,'extra_cashboxes',p_extra_cashboxes,'extra_users',p_extra_users,'period_end',p_period_end));
 return jsonb_build_object('ok',true,'action',p_action);
end $$;
revoke all on function public.enhar_admin_manage_subscription(uuid,text,text,text,integer,integer,timestamptz) from public,anon;
grant execute on function public.enhar_admin_manage_subscription(uuid,text,text,text,integer,integer,timestamptz) to authenticated;

create or replace function public.enhar_enforce_company_user_limit()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_limit integer;
begin
 if new.status<>'ACTIVE' then return new; end if;
 select coalesce(p.user_limit,9)+coalesce(s.extra_users,0) into v_limit
 from public.enhar_companies c
 left join public.enhar_company_subscriptions s on s.company_id=c.id
 left join public.enhar_subscription_plans p on p.id=s.plan_id
 where c.id=new.company_id and c.status='ACTIVE';
 if v_limit is null then raise exception 'Company is suspended or unavailable'; end if;
 if (select count(*) from public.enhar_company_memberships m where m.company_id=new.company_id and m.status='ACTIVE' and (tg_op='INSERT' or m.id<>new.id))>=v_limit then
  raise exception 'USER_LIMIT_REACHED: Upgrade plan or purchase additional users';
 end if;
 return new;
end $$;
drop trigger if exists enhar_company_user_quota on public.enhar_company_memberships;
create trigger enhar_company_user_quota before insert or update of status on public.enhar_company_memberships
for each row execute function public.enhar_enforce_company_user_limit();

create or replace function public.enhar_enforce_company_cashbox_limit()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_limit integer;
begin
 if new.is_active is not true then return new; end if;
 select coalesce(p.cashbox_limit,2)+coalesce(s.extra_cashboxes,0) into v_limit
 from public.enhar_companies c
 left join public.enhar_company_subscriptions s on s.company_id=c.id
 left join public.enhar_subscription_plans p on p.id=s.plan_id
 where c.id=new.company_id and c.status='ACTIVE';
 if v_limit is null then raise exception 'Company is suspended or unavailable'; end if;
 if (select count(*) from public.enhar_cashboxes b where b.company_id=new.company_id and b.is_active=true and (tg_op='INSERT' or b.id<>new.id))>=v_limit then
  raise exception 'CASHBOX_LIMIT_REACHED: Upgrade plan or purchase additional cashboxes';
 end if;
 return new;
end $$;
drop trigger if exists enhar_company_cashbox_quota on public.enhar_cashboxes;
create trigger enhar_company_cashbox_quota before insert or update of is_active on public.enhar_cashboxes
for each row execute function public.enhar_enforce_company_cashbox_limit();

-- Update payment fulfillment to grant the purchased term; add-on checkout fulfillment is handled separately.
create or replace function public.enhar_apply_moyasar_invoice_payment(
 p_order_id uuid,p_invoice_id text,p_amount_halalas integer,p_currency text,p_invoice_status text
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_order public.enhar_subscription_orders%rowtype; v_plan public.enhar_subscription_plans%rowtype; v_end timestamptz;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
 select * into v_order from public.enhar_subscription_orders where id=p_order_id for update;
 if not found then raise exception 'Subscription order not found'; end if;
 if v_order.provider_invoice_id is not null and v_order.provider_invoice_id<>p_invoice_id then raise exception 'Invoice does not match order'; end if;
 if upper(p_invoice_status)<>'PAID' then
  update public.enhar_subscription_orders set status=case when upper(p_invoice_status) in ('FAILED','EXPIRED','CANCELED','VOIDED') then 'FAILED' else status end,provider_invoice_id=coalesce(provider_invoice_id,p_invoice_id),updated_at=now() where id=p_order_id;
  return jsonb_build_object('ok',true,'status','NOT_PAID');
 end if;
 if p_amount_halalas<>v_order.amount_halalas or upper(p_currency)<>v_order.currency then raise exception 'Payment amount or currency mismatch'; end if;
 if v_order.status='PAID' then return jsonb_build_object('ok',true,'status','ALREADY_APPLIED'); end if;
 if v_order.order_type='PLAN' then
  select * into v_plan from public.enhar_subscription_plans where id=v_order.plan_id;
  v_end:=now()+case when v_order.duration_months=12 then interval '1 year' else interval '6 months' end;
  insert into public.enhar_company_subscriptions(company_id,plan_id,status,current_period_start,current_period_end,last_order_id,updated_at)
  values(v_order.company_id,v_order.plan_id,'ACTIVE',now(),v_end,p_order_id,now())
  on conflict(company_id) do update set plan_id=excluded.plan_id,status='ACTIVE',
   current_period_start=case when public.enhar_company_subscriptions.current_period_end>now() then public.enhar_company_subscriptions.current_period_start else now() end,
   current_period_end=greatest(public.enhar_company_subscriptions.current_period_end,now())+case when v_order.duration_months=12 then interval '1 year' else interval '6 months' end,
   last_order_id=p_order_id,updated_at=now();
 elsif v_order.order_type='ADDON_CASHBOX' then
  update public.enhar_company_subscriptions set extra_cashboxes=extra_cashboxes+v_order.quantity,updated_at=now() where company_id=v_order.company_id;
 elsif v_order.order_type='ADDON_USER' then
  update public.enhar_company_subscriptions set extra_users=extra_users+v_order.quantity,updated_at=now() where company_id=v_order.company_id;
 end if;
 update public.enhar_subscription_orders set status='PAID',provider_invoice_id=p_invoice_id,paid_at=now(),updated_at=now() where id=p_order_id;
 update public.enhar_companies set subscription_status='ACTIVE',status='ACTIVE',updated_at=now() where id=v_order.company_id;
 return jsonb_build_object('ok',true,'status','PAID','company_id',v_order.company_id,'period_end',v_end);
end $function$;
revoke all on function public.enhar_apply_moyasar_invoice_payment(uuid,text,integer,text,text) from public,anon,authenticated;
grant execute on function public.enhar_apply_moyasar_invoice_payment(uuid,text,integer,text,text) to service_role;

commit;
