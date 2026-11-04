-- ENHAR BUSINESS: verify the signed-in user's platform administrator role.
-- Run this once in Supabase SQL Editor as project owner.
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM platform.platform_admins AS pa
    WHERE pa.user_id = (SELECT auth.uid())
      AND pa.admin_role = 'SUPER_ADMIN'
  );
$function$;

REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;
