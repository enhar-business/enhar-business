import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405, headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return Response.json({ error: "Sign in required" }, { status: 401, headers: cors });

    const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: authError } = await caller.auth.getUser();
    if (authError || !user) return Response.json({ error: "Invalid session" }, { status: 401, headers: cors });
    const { data: isAdmin, error: roleError } = await caller.rpc("is_platform_admin");
    if (roleError || isAdmin !== true) return Response.json({ error: "Platform administrator permission required" }, { status: 403, headers: cors });

    const body = await req.json();
    const email = String(body.email || "").trim().toLowerCase();
    const fullName = String(body.full_name || "").trim();
    const companyName = String(body.company_name || "").trim();
    const password = String(body.temporary_password || "");
    const periodEnd = body.period_end ? new Date(body.period_end) : new Date(Date.now() + 365 * 86400000);
    if (!email.includes("@") || fullName.length < 2 || companyName.length < 2) return Response.json({ error: "الاسم والبريد واسم المنشأة مطلوبة" }, { status: 400, headers: cors });
    if (password.length < 12) return Response.json({ error: "كلمة المرور المؤقتة يجب ألا تقل عن 12 خانة" }, { status: 400, headers: cors });
    if (Number.isNaN(periodEnd.getTime()) || periodEnd <= new Date()) return Response.json({ error: "تاريخ نهاية الاشتراك غير صالح" }, { status: 400, headers: cors });

    const admin = createClient(url, serviceKey);
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email, password, email_confirm: true,
      user_metadata: { full_name: fullName, company_name: companyName, created_by_platform_admin: true },
    });
    if (createError || !created.user) return Response.json({ error: createError?.message || "تعذر إنشاء حساب الدخول" }, { status: 400, headers: cors });

    const { data: company, error: companyError } = await admin.rpc("enhar_admin_create_managed_company", {
      p_owner_user_id: created.user.id,
      p_name_ar: companyName,
      p_name_en: body.company_name_en ? String(body.company_name_en).trim() : null,
      p_period_end: periodEnd.toISOString(),
    });
    if (companyError) {
      await admin.auth.admin.deleteUser(created.user.id);
      throw companyError;
    }
    return Response.json({ ok: true, user_id: created.user.id, email, company }, { headers: cors });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Unexpected error" }, { status: 500, headers: cors });
  }
});
