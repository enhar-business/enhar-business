import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const moyasarKey = Deno.env.get("MOYASAR_SECRET_KEY");
    if (!moyasarKey) throw new Error("Payment provider is not configured");

    const event = await req.json();
    const invoiceId = String(event.id || event.data?.invoice_id || "");
    if (!invoiceId) return Response.json({ error: "Missing invoice id" }, { status: 400 });

    // Never trust the webhook body alone: retrieve the invoice directly from Moyasar.
    const response = await fetch("https://api.moyasar.com/v1/invoices/" + encodeURIComponent(invoiceId), {
      headers: { "Authorization": "Basic " + btoa(moyasarKey + ":") },
    });
    const invoice = await response.json();
    if (!response.ok || invoice.id !== invoiceId) return Response.json({ error: "Could not verify provider invoice" }, { status: 401 });

    const orderId = String(invoice.metadata?.enhar_order_id || "");
    if (!orderId) return Response.json({ error: "Missing ENHAR order metadata" }, { status: 400 });

    const admin = createClient(url, serviceKey);
    const { data: order, error } = await admin.from("enhar_subscription_orders")
      .select("id,provider_invoice_id,amount_halalas,currency,status")
      .eq("id", orderId).single();
    if (error || !order) return Response.json({ error: "Unknown subscription order" }, { status: 404 });
    if (order.provider_invoice_id && order.provider_invoice_id !== invoice.id) {
      return Response.json({ error: "Invoice/order mismatch" }, { status: 409 });
    }

    const statusMap: Record<string, string> = {
      paid: "PAID", failed: "FAILED", expired: "EXPIRED", canceled: "FAILED", voided: "FAILED", refunded: "REFUNDED",
    };
    const normalized = statusMap[String(invoice.status || "").toLowerCase()] || "PENDING";

    if (normalized === "PAID") {
      const { error: applyError } = await admin.rpc("enhar_apply_moyasar_invoice_payment", {
        p_order_id: order.id,
        p_invoice_id: invoice.id,
        p_amount_halalas: Number(invoice.amount),
        p_currency: String(invoice.currency || ""),
        p_invoice_status: "PAID",
      });
      if (applyError) throw applyError;
    } else if (normalized !== "PENDING") {
      await admin.from("enhar_subscription_orders")
        .update({ status: normalized, provider_invoice_id: invoice.id, updated_at: new Date().toISOString() })
        .eq("id", order.id).neq("status", "PAID");
    }
    return Response.json({ received: true, status: normalized });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Webhook processing failed" }, { status: 500 });
  }
});
