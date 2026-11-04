-- ENHAR BUSINESS | Subscription billing foundation (Moyasar)
begin;

create table if not exists public.enhar_subscription_plans (
  id uuid primary key default gen_random_uuid(),
  plan_code text not null unique,
  name_ar text not null,
  name_en text,
  billing_period text not null check (billing_period in ('MONTHLY','YEARLY','TEST')),
  amount_halalas integer not null check (amount_halalas >= 100),
  currency char(3) not null default 'SAR',
  is_test boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.enhar_subscription_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.enhar_companies(id) on delete restrict,
  plan_id uuid not null references public.enhar_subscription_plans(id) on delete restrict,
  amount_halalas integer not null check (amount_halalas >= 100),
  currency char(3) not null default 'SAR',
  status text not null default 'PENDING' check (status in ('PENDING','PAID','FAILED','REFUNDED','EXPIRED')),
  provider text not null default 'MOYASAR',
  provider_invoice_id text unique,
  checkout_url text,
  paid_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.enhar_company_subscriptions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null unique references public.enhar_companies(id) on delete restrict,
  plan_id uuid not null references public.enhar_subscription_plans(id) on delete restrict,
  status text not null check (status in ('ACTIVE','PAST_DUE','CANCELLED','EXPIRED')),
  current_period_start timestamptz not null,
  current_period_end timestamptz not null,
  last_order_id uuid references public.enhar_subscription_orders(id),
  updated_at timestamptz not null default now()
);

create index if not exists enhar_subscription_orders_company_idx
  on public.enhar_subscription_orders(company_id, created_at desc);

alter table public.enhar_subscription_plans enable row level security;
alter table public.enhar_subscription_orders enable row level security;
alter table public.enhar_company_subscriptions enable row level security;

drop policy if exists enhar_subscription_plans_read on public.enhar_subscription_plans;
create policy enhar_subscription_plans_read on public.enhar_subscription_plans
for select to authenticated using (is_active = true or public.is_platform_admin());

drop policy if exists enhar_subscription_orders_read on public.enhar_subscription_orders;
create policy enhar_subscription_orders_read on public.enhar_subscription_orders
for select to authenticated using (public.enhar_is_company_admin(company_id) or public.is_platform_admin());

drop policy if exists enhar_company_subscriptions_read on public.enhar_company_subscriptions;
create policy enhar_company_subscriptions_read on public.enhar_company_subscriptions
for select to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin());

revoke all on public.enhar_subscription_plans, public.enhar_subscription_orders, public.enhar_company_subscriptions from anon, authenticated;
grant select on public.enhar_subscription_plans, public.enhar_subscription_orders, public.enhar_company_subscriptions to authenticated;

create or replace function public.enhar_apply_moyasar_invoice_payment(
  p_order_id uuid,
  p_invoice_id text,
  p_amount_halalas integer,
  p_currency text,
  p_invoice_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.enhar_subscription_orders%rowtype;
  v_period text;
  v_end timestamptz;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Service role required';
  end if;

  select * into v_order from public.enhar_subscription_orders where id=p_order_id for update;
  if not found then raise exception 'Subscription order not found'; end if;

  if v_order.provider_invoice_id is not null and v_order.provider_invoice_id <> p_invoice_id then
    raise exception 'Invoice does not match order';
  end if;

  if upper(p_invoice_status) <> 'PAID' then
    update public.enhar_subscription_orders
      set status=case when upper(p_invoice_status) in ('FAILED','EXPIRED','CANCELED','VOIDED') then 'FAILED' else status end,
          provider_invoice_id=coalesce(provider_invoice_id,p_invoice_id),updated_at=now()
      where id=p_order_id;
    return jsonb_build_object('ok',true,'status','NOT_PAID');
  end if;

  if p_amount_halalas <> v_order.amount_halalas or upper(p_currency) <> v_order.currency then
    raise exception 'Payment amount or currency mismatch';
  end if;

  if v_order.status='PAID' then
    return jsonb_build_object('ok',true,'status','ALREADY_APPLIED');
  end if;

  select billing_period into v_period from public.enhar_subscription_plans where id=v_order.plan_id;
  v_end := now() + case when v_period='YEARLY' then interval '1 year' else interval '1 month' end;

  update public.enhar_subscription_orders
    set status='PAID',provider_invoice_id=p_invoice_id,paid_at=now(),updated_at=now()
    where id=p_order_id;

  insert into public.enhar_company_subscriptions(company_id,plan_id,status,current_period_start,current_period_end,last_order_id,updated_at)
  values(v_order.company_id,v_order.plan_id,'ACTIVE',now(),v_end,p_order_id,now())
  on conflict(company_id) do update set
    plan_id=excluded.plan_id,status='ACTIVE',
    current_period_start=case when public.enhar_company_subscriptions.current_period_end>now()
      then public.enhar_company_subscriptions.current_period_start else now() end,
    current_period_end=greatest(public.enhar_company_subscriptions.current_period_end,now())
      + case when v_period='YEARLY' then interval '1 year' else interval '1 month' end,
    last_order_id=p_order_id,updated_at=now();

  update public.enhar_companies
    set subscription_status='ACTIVE',status='ACTIVE',updated_at=now()
    where id=v_order.company_id;

  return jsonb_build_object('ok',true,'status','PAID','company_id',v_order.company_id,'period_end',v_end);
end;
$function$;

revoke all on function public.enhar_apply_moyasar_invoice_payment(uuid,text,integer,text,text) from public,anon,authenticated;
grant execute on function public.enhar_apply_moyasar_invoice_payment(uuid,text,integer,text,text) to service_role;

-- One low-value sandbox plan for integration testing only. Never visible to customers.
insert into public.enhar_subscription_plans(plan_code,name_ar,name_en,billing_period,amount_halalas,currency,is_test,is_active)
values('SANDBOX-1SAR','اختبار بوابة الدفع (تجريبي)','Payment gateway test','TEST',100,'SAR',true,false)
on conflict(plan_code) do nothing;

commit;
