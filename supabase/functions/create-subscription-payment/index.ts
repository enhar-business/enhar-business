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
    const moyasarKey = Deno.env.get("MOYASAR_SECRET_KEY");
    const siteUrl = Deno.env.get("ENHAR_SITE_URL");
    if (!moyasarKey || !siteUrl) throw new Error("Payment provider is not configured");

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return Response.json({ error: "Sign in required" }, { status: 401, headers: cors });
    const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) return Response.json({ error: "Invalid session" }, { status: 401, headers: cors });

    const body = await req.json();
    const companyId = String(body.company_id || "");
    const planId = String(body.plan_id || "");
    if (!companyId || !planId) return Response.json({ error: "company_id and plan_id are required" }, { status: 400, headers: cors });

    const admin = createClient(url, serviceKey);
    const { data: membership, error: membershipError } = await admin
      .from("enhar_company_memberships").select("role,status")
      .eq("company_id", companyId).eq("user_id", user.id).maybeSingle();
    if (membershipError || !membership || membership.status !== "ACTIVE" || !["OWNER", "ADMIN"].includes(membership.role)) {
      return Response.json({ error: "Company owner or admin permission required" }, { status: 403, headers: cors });
    }

    const { data: plan, error: planError } = await admin.from("enhar_subscription_plans")
      .select("id,plan_code,name_ar,billing_period,amount_halalas,currency,is_test,is_active,cashbox_limit,user_limit")
      .eq("id", planId).eq("is_active", true).single();
    if (planError || !plan || plan.is_test || !["SIX_MONTHS", "YEARLY"].includes(plan.billing_period)) {
      return Response.json({ error: "Selected subscription plan is unavailable" }, { status: 400, headers: cors });
    }

    const { data: order, error: orderError } = await admin.from("enhar_subscription_orders")
      .insert({ company_id: companyId, plan_id: plan.id, amount_halalas: plan.amount_halalas, currency: plan.currency, created_by: user.id, order_type: "PLAN", duration_months: plan.billing_period === "YEARLY" ? 12 : 6 })
      .select("id").single();
    if (orderError || !order) throw orderError || new Error("Could not create subscription order");

    const callbackUrl = url + "/functions/v1/moyasar-invoice-callback";
    const successUrl = siteUrl.replace(/\/$/, "") + "/billing.html?order=" + order.id;
    const payload = {
      amount: plan.amount_halalas,
      currency: plan.currency,
      description: "ENHAR BUSINESS - " + plan.name_ar,
      callback_url: callbackUrl,
      success_url: successUrl,
      back_url: successUrl,
      expired_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
      metadata: { enhar_order_id: order.id, enhar_company_id: companyId, enhar_plan_code: plan.plan_code },
    };
    const auth = btoa(moyasarKey + ":");
    const response = await fetch("https://api.moyasar.com/v1/invoices", {
      method: "POST",
      headers: { "Authorization": "Basic " + auth, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const invoice = await response.json();
    if (!response.ok || !invoice.id || !invoice.url) {
      await admin.from("enhar_subscription_orders").update({ status: "FAILED" }).eq("id", order.id);
      return Response.json({ error: invoice.message || "Payment provider rejected invoice" }, { status: 502, headers: cors });
    }

    const { error: updateError } = await admin.from("enhar_subscription_orders")
      .update({ provider_invoice_id: invoice.id, checkout_url: invoice.url, updated_at: new Date().toISOString() })
      .eq("id", order.id);
    if (updateError) throw updateError;

    return Response.json({ order_id: order.id, checkout_url: invoice.url, amount_halalas: plan.amount_halalas, currency: plan.currency }, { headers: cors });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Unexpected error" }, { status: 500, headers: cors });
  }
});
