-- ANHAR migration 003: grant read access where RLS policies intentionally allow it.
begin;
grant select on public.subscription_plans to authenticated;
grant select on public.subscription_addon_catalog to authenticated;
grant select on public.company_subscriptions to authenticated;
commit;
