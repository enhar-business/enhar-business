-- ENHAR BUSINESS | platform company administration
-- Adds secure SUPER_ADMIN company onboarding and lifecycle controls.
begin;

create or replace function public.enhar_admin_create_company(
  p_name_ar text,
  p_owner_email text,
  p_name_en text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin uuid := auth.uid();
  v_owner uuid;
  v_owner_name text;
  v_company uuid;
  v_branch uuid;
  v_code text;
  v_trial_end timestamptz;
begin
  if v_admin is null or not public.is_platform_admin() then
    raise exception 'Platform administrator permission required';
  end if;
  if p_name_ar is null or char_length(trim(p_name_ar)) < 2 or char_length(trim(p_name_ar)) > 200 then
    raise exception 'Company name must be between 2 and 200 characters';
  end if;
  if p_owner_email is null or position('@' in trim(p_owner_email)) < 2 then
    raise exception 'A valid owner email is required';
  end if;

  select u.id, u.raw_user_meta_data->>'full_name' into v_owner, v_owner_name
  from auth.users u
  where lower(u.email) = lower(trim(p_owner_email))
  limit 1;
  if v_owner is null then
    raise exception 'No registered account exists for this owner email. Ask the owner to register first.';
  end if;

  v_code := 'ENH-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  insert into public.enhar_companies(company_code,name_ar,name_en,created_by,trial_started_at,trial_ends_at)
  values(v_code,trim(p_name_ar),nullif(trim(coalesce(p_name_en,'')),''),v_admin,now(),now()+interval '15 days')
  returning id,trial_ends_at into v_company,v_trial_end;

  insert into public.enhar_company_memberships(company_id,user_id,role,status)
  values(v_company,v_owner,'OWNER','ACTIVE');

  insert into public.enhar_branches(company_id,branch_code,name_ar,name_en)
  values(v_company,'MAIN','الفرع الرئيسي','Main Branch')
  returning id into v_branch;

  insert into public.enhar_warehouses(company_id,branch_id,warehouse_code,name_ar,name_en)
  values(v_company,v_branch,'MAIN','المستودع الرئيسي','Main Warehouse');

  insert into public.enhar_profiles(user_id,full_name,phone)
  values(v_owner,nullif(v_owner_name,''),null)
  on conflict(user_id) do update set full_name=coalesce(public.enhar_profiles.full_name,excluded.full_name);

  return jsonb_build_object('company_id',v_company,'company_code',v_code,'owner_user_id',v_owner,'trial_days',15,'trial_ends_at',v_trial_end);
end;
$function$;

create or replace function public.enhar_admin_set_company_status(
  p_company_id uuid,
  p_status text,
  p_subscription_status text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.enhar_companies%rowtype;
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'Platform administrator permission required';
  end if;
  if p_status not in ('ACTIVE','SUSPENDED','CLOSED') then
    raise exception 'Invalid company status';
  end if;
  if p_subscription_status is not null and p_subscription_status not in ('TRIAL','ACTIVE','PAST_DUE','SUSPENDED','CANCELLED') then
    raise exception 'Invalid subscription status';
  end if;
  update public.enhar_companies
  set status=p_status,
      subscription_status=coalesce(p_subscription_status,subscription_status),
      updated_at=now()
  where id=p_company_id
  returning * into v_row;
  if not found then raise exception 'Company not found'; end if;
  return jsonb_build_object('company_id',v_row.id,'status',v_row.status,'subscription_status',v_row.subscription_status);
end;
$function$;

revoke all on function public.enhar_admin_create_company(text,text,text) from public,anon;
revoke all on function public.enhar_admin_set_company_status(uuid,text,text) from public,anon;
grant execute on function public.enhar_admin_create_company(text,text,text) to authenticated;
grant execute on function public.enhar_admin_set_company_status(uuid,text,text) to authenticated;

commit;
