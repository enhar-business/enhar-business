-- ENHAR BUSINESS | Controlled cashbox operations (phase 2)
-- Run after 20261104000500_sales_registers_and_settings.sql.
begin;

-- Tighten direct table access: cashbox/settings configuration is admin-only.
drop policy if exists enhar_cashboxes_member_access on public.enhar_cashboxes;
create policy enhar_cashboxes_read on public.enhar_cashboxes
for select to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin());
create policy enhar_cashboxes_admin_write on public.enhar_cashboxes
for all to authenticated using (public.enhar_is_company_admin(company_id) or public.is_platform_admin())
with check (public.enhar_is_company_admin(company_id) or public.is_platform_admin());

drop policy if exists enhar_cash_settings_member_access on public.enhar_cash_settings;
create policy enhar_cash_settings_read on public.enhar_cash_settings
for select to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin());
create policy enhar_cash_settings_admin_write on public.enhar_cash_settings
for all to authenticated using (public.enhar_is_company_admin(company_id) or public.is_platform_admin())
with check (public.enhar_is_company_admin(company_id) or public.is_platform_admin());

drop policy if exists enhar_invoice_settings_member_access on public.enhar_invoice_settings;
create policy enhar_invoice_settings_read on public.enhar_invoice_settings
for select to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin());
create policy enhar_invoice_settings_admin_write on public.enhar_invoice_settings
for all to authenticated using (public.enhar_is_company_admin(company_id) or public.is_platform_admin())
with check (public.enhar_is_company_admin(company_id) or public.is_platform_admin());

drop policy if exists enhar_promotions_member_access on public.enhar_promotions;
create policy enhar_promotions_read on public.enhar_promotions
for select to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin());
create policy enhar_promotions_admin_write on public.enhar_promotions
for all to authenticated using (public.enhar_is_company_admin(company_id) or public.is_platform_admin())
with check (public.enhar_is_company_admin(company_id) or public.is_platform_admin());

drop policy if exists enhar_cash_sessions_member_access on public.enhar_cash_sessions;
create policy enhar_cash_sessions_read on public.enhar_cash_sessions
for select to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin());

drop policy if exists enhar_cash_movements_member_access on public.enhar_cash_movements;
create policy enhar_cash_movements_read on public.enhar_cash_movements
for select to authenticated using (public.enhar_is_company_member(company_id) or public.is_platform_admin());

revoke insert,update,delete on public.enhar_cash_sessions,public.enhar_cash_movements from authenticated;
revoke insert,update,delete on public.enhar_cash_settings,public.enhar_invoice_settings,public.enhar_promotions from authenticated;
grant select on public.enhar_cash_sessions,public.enhar_cash_movements to authenticated;
grant select,insert,update,delete on public.enhar_cash_settings,public.enhar_invoice_settings,public.enhar_promotions to authenticated;

create or replace function public.enhar_admin_upsert_cashbox(
 p_company_id uuid,p_branch_id uuid,p_code text,p_name_ar text,p_cashbox_id uuid default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if auth.uid() is null or not (public.enhar_is_company_admin(p_company_id) or public.is_platform_admin()) then raise exception 'Admin permission required'; end if;
 if length(trim(coalesce(p_code,'')))<2 or length(trim(coalesce(p_name_ar,'')))<2 then raise exception 'Code and name are required'; end if;
 if not exists(select 1 from public.enhar_branches b where b.company_id=p_company_id and b.id=p_branch_id and b.is_active) then raise exception 'Invalid branch'; end if;
 if p_cashbox_id is null then
  insert into public.enhar_cashboxes(company_id,branch_id,code,name_ar) values(p_company_id,p_branch_id,upper(trim(p_code)),trim(p_name_ar)) returning id into v_id;
 else
  update public.enhar_cashboxes set branch_id=p_branch_id,code=upper(trim(p_code)),name_ar=trim(p_name_ar)
  where company_id=p_company_id and id=p_cashbox_id returning id into v_id;
  if v_id is null then raise exception 'Cashbox not found'; end if;
 end if;
 return v_id;
end $$;

create or replace function public.enhar_open_cash_session(
 p_company_id uuid,p_cashbox_id uuid,p_opening_amount numeric,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_box public.enhar_cashboxes%rowtype; v_settings public.enhar_cash_settings%rowtype; v_id uuid;
begin
 if auth.uid() is null or not public.enhar_is_company_member(p_company_id) then raise exception 'Membership required'; end if;
 select * into v_box from public.enhar_cashboxes where company_id=p_company_id and id=p_cashbox_id and is_active for update;
 if not found then raise exception 'Active cashbox not found'; end if;
 select * into v_settings from public.enhar_cash_settings where company_id=p_company_id;
 if found and not v_settings.allow_open and not (public.enhar_is_company_admin(p_company_id) or public.is_platform_admin()) then raise exception 'Opening cash sessions is disabled by company policy'; end if;
 if exists(select 1 from public.enhar_cash_sessions where company_id=p_company_id and cashbox_id=p_cashbox_id and status='OPEN') then raise exception 'This cashbox already has an open session'; end if;
 if p_opening_amount is null or p_opening_amount<0 then raise exception 'Opening amount must be zero or greater'; end if;
 insert into public.enhar_cash_sessions(company_id,cashbox_id,branch_id,opened_by,opening_amount,expected_amount,notes)
 values(p_company_id,p_cashbox_id,v_box.branch_id,auth.uid(),p_opening_amount,p_opening_amount,p_notes) returning id into v_id;
 insert into public.enhar_cash_movements(company_id,session_id,movement_type,amount,payment_method,notes)
 values(p_company_id,v_id,'OPENING',p_opening_amount,'CASH','رصيد افتتاحي');
 return jsonb_build_object('session_id',v_id,'status','OPEN','opening_amount',p_opening_amount);
end $$;

create or replace function public.enhar_add_cash_movement(
 p_company_id uuid,p_session_id uuid,p_movement_type text,p_amount numeric,p_payment_method text default 'CASH',p_notes text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_session public.enhar_cash_sessions%rowtype; v_id uuid;
begin
 if auth.uid() is null or not public.enhar_is_company_member(p_company_id) then raise exception 'Membership required'; end if;
 if p_movement_type not in ('CASH_IN','CASH_OUT','SALE','REFUND') then raise exception 'Unsupported movement type'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Amount must be greater than zero'; end if;
 select * into v_session from public.enhar_cash_sessions where company_id=p_company_id and id=p_session_id for update;
 if not found or v_session.status<>'OPEN' then raise exception 'Open session not found'; end if;
 insert into public.enhar_cash_movements(company_id,session_id,movement_type,amount,payment_method,notes,created_by)
 values(p_company_id,p_session_id,p_movement_type,p_amount,coalesce(p_payment_method,'CASH'),p_notes,auth.uid()) returning id into v_id;
 update public.enhar_cash_sessions set expected_amount=opening_amount+
  coalesce((select sum(case when movement_type in ('SALE','CASH_IN') then amount when movement_type in ('REFUND','CASH_OUT') then -amount else 0 end)
  from public.enhar_cash_movements where company_id=p_company_id and session_id=p_session_id),0)
 where company_id=p_company_id and id=p_session_id;
 return v_id;
end $$;

create or replace function public.enhar_close_cash_session(
 p_company_id uuid,p_session_id uuid,p_actual_amount numeric,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_session public.enhar_cash_sessions%rowtype; v_expected numeric(14,2); v_diff numeric(14,2); v_settings public.enhar_cash_settings%rowtype;
begin
 if auth.uid() is null or not public.enhar_is_company_member(p_company_id) then raise exception 'Membership required'; end if;
 select * into v_session from public.enhar_cash_sessions where company_id=p_company_id and id=p_session_id for update;
 if not found or v_session.status<>'OPEN' then raise exception 'Open session not found'; end if;
 select * into v_settings from public.enhar_cash_settings where company_id=p_company_id;
 if found and not v_settings.allow_close and not (public.enhar_is_company_admin(p_company_id) or public.is_platform_admin()) then raise exception 'Closing cash sessions is disabled by company policy'; end if;
 if p_actual_amount is null or p_actual_amount<0 then raise exception 'Actual amount must be zero or greater'; end if;
 select v_session.opening_amount+
  coalesce(sum(case when movement_type in ('SALE','CASH_IN') then amount when movement_type in ('REFUND','CASH_OUT') then -amount else 0 end),0)
 into v_expected from public.enhar_cash_movements where company_id=p_company_id and session_id=p_session_id;
 v_diff:=round(p_actual_amount-v_expected,2);
 if coalesce(v_settings.require_balance_approval,false) and v_diff<>0 and not (public.enhar_is_company_admin(p_company_id) or public.is_platform_admin()) then raise exception 'Balance difference requires administrator approval'; end if;
 update public.enhar_cash_sessions set status='CLOSED',closed_at=now(),closed_by=auth.uid(),expected_amount=v_expected,actual_amount=p_actual_amount,difference=v_diff,notes=concat_ws(E'\n',notes,p_notes)
 where company_id=p_company_id and id=p_session_id;
 insert into public.enhar_cash_movements(company_id,session_id,movement_type,amount,payment_method,notes)
 values(p_company_id,p_session_id,'CLOSING',p_actual_amount,'CASH','إقفال فعلي');
 return jsonb_build_object('session_id',p_session_id,'expected_amount',v_expected,'actual_amount',p_actual_amount,'difference',v_diff,'balanced',v_diff=0);
end $$;

create or replace function public.enhar_cash_session_report(p_company_id uuid,p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_session public.enhar_cash_sessions%rowtype; v_moves jsonb;
begin
 if auth.uid() is null or not public.enhar_is_company_member(p_company_id) then raise exception 'Membership required'; end if;
 select * into v_session from public.enhar_cash_sessions where company_id=p_company_id and id=p_session_id;
 if not found then raise exception 'Session not found'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('movement_type',m.movement_type,'amount',m.amount,'payment_method',m.payment_method,'notes',m.notes,'created_at',m.created_at) order by m.created_at),'[]'::jsonb)
 into v_moves from public.enhar_cash_movements m where m.company_id=p_company_id and m.session_id=p_session_id;
 return jsonb_build_object('session',to_jsonb(v_session),'movements',v_moves);
end $$;

revoke all on function public.enhar_admin_upsert_cashbox(uuid,uuid,text,text,uuid) from public,anon;
revoke all on function public.enhar_open_cash_session(uuid,uuid,numeric,text) from public,anon;
revoke all on function public.enhar_add_cash_movement(uuid,uuid,text,numeric,text,text) from public,anon;
revoke all on function public.enhar_close_cash_session(uuid,uuid,numeric,text) from public,anon;
revoke all on function public.enhar_cash_session_report(uuid,uuid) from public,anon;
grant execute on function public.enhar_admin_upsert_cashbox(uuid,uuid,text,text,uuid) to authenticated;
grant execute on function public.enhar_open_cash_session(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.enhar_add_cash_movement(uuid,uuid,text,numeric,text,text) to authenticated;
grant execute on function public.enhar_close_cash_session(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.enhar_cash_session_report(uuid,uuid) to authenticated;
commit;
