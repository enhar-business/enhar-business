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
    if (body.action === "reset_password") {
      const userId = String(body.user_id || "");
      const password = String(body.temporary_password || "");
      if (!userId || password.length < 12) return Response.json({ error: "معرّف المستخدم وكلمة مرور من 12 خانة على الأقل مطلوبان" }, { status: 400, headers: cors });
      const admin = createClient(url, serviceKey);
      const { data: updated, error: updateError } = await admin.auth.admin.updateUserById(userId, { password });
      if (updateError || !updated.user) throw updateError || new Error("تعذر تحديث كلمة المرور");
      return Response.json({ ok: true, user_id: userId }, { headers: cors });
    }
    if (body.action === "list_subscribers") {
      const admin = createClient(url, serviceKey);
      const { data: companies, error: companiesError } = await admin.from("enhar_companies")
        .select("id,company_code,name_ar,status,subscription_status,trial_ends_at,created_at,enhar_company_memberships(user_id,role,status)")
        .order("created_at", { ascending: false }).limit(500);
      if (companiesError) throw companiesError;
      const rows = [];
      for (const company of companies || []) {
        const owner = (company.enhar_company_memberships || []).find((m: any) => m.role === "OWNER" && m.status === "ACTIVE");
        let email = "";
        if (owner?.user_id) {
          const { data: authUser } = await admin.auth.admin.getUserById(owner.user_id);
          email = authUser.user?.email || "";
        }
        rows.push({ ...company, owner_email: email, owner_user_id: owner?.user_id || null, enhar_company_memberships: undefined });
      }
      return Response.json({ ok: true, subscribers: rows }, { headers: cors });
    }
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
