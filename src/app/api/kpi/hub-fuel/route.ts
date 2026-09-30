import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// KPI reads the canonical Hub fuel transactions. B.Smart credentials and polling
// remain owned by Hub; KPI must never call PIUSI or count unverified prices.
export async function GET() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Inloggning krävs." }, { status: 401 });
  const { data: member } = await supabase.from("hub_tenant_members")
    .select("tenant_id").eq("user_id", user.id).eq("status", "active").maybeSingle();
  if (!member) return Response.json({ error: "Aktivt företag saknas." }, { status: 403 });
  const { data: allowed, error: permissionError } = await supabase.rpc("hub_has_permission", {
    p_tenant_id: member.tenant_id, p_permission: "kpi.read",
  });
  if (permissionError || !allowed) return Response.json({ error: "Behörighet saknas." }, { status: 403 });
  const { data: connection, error: connectionError } = await supabase.from("hub_connections")
    .select("status,last_success_at,last_error_at").eq("tenant_id", member.tenant_id)
    .eq("connector_type", "piusi_bsmart").maybeSingle();
  if (connectionError) return Response.json({ error: "B.Smart-anslutningen kunde inte läsas." }, { status: 500 });
  const { data: objects, error } = await supabase.from("kpi_bsmart_fuel_checked_v1")
    .select("*").eq("tenant_id", member.tenant_id)
    .order("updated_at", { ascending: false }).limit(5000);
  if (error) return Response.json({ error: "Tankningar kunde inte hämtas från Humla Hub." }, { status: 500 });
  const transactions = (objects ?? []).map((item) => ({
    id: item.hub_object_id,
    transactionId: item.transaction_id,
    occurredAt: item.occurred_at,
    registration: item.vehicle_registration,
    liters: item.liters == null ? null : Number(item.liters),
    provisionalCostSek: item.accepted_cost_sek == null ? null : Number(item.accepted_cost_sek),
    rawCostSek: item.bsmart_cost_sek == null ? null : Number(item.bsmart_cost_sek),
    reviewReason: item.review_reason,
    costStatus: item.cost_status,
    priceStatus: item.price_status,
    updatedAt: item.updated_at,
  }));
  return Response.json({
    source: "humla_hub/piusi_bsmart",
    connectionStatus: connection?.status ?? "not_configured",
    lastConnectorSuccess: connection?.last_success_at ?? null,
    lastTransactionUpdate: transactions[0]?.updatedAt ?? null,
    live: connection?.status === "active" && Boolean(connection.last_success_at) &&
      Date.now() - new Date(connection.last_success_at).getTime() < 2 * 60 * 60 * 1000,
    count: transactions.length,
    liters: transactions.reduce((sum, item) => sum + (item.liters ?? 0), 0),
    provisionalBsmartCostSek: transactions.reduce((sum, item) => sum + (item.provisionalCostSek ?? 0), 0),
    manualReviewCount: transactions.filter(item => item.reviewReason).length,
    excludedSuspiciousCostSek: transactions.filter(item => item.reviewReason).reduce((sum,item) => sum + (item.rawCostSek ?? 0),0),
    costSource: "B.Smart source_amount; provisional until source price is verified",
    nextAccount5360: "reconciliation_only_no_additional_cost",
    transactions,
  }, { headers: { "Cache-Control": "no-store" } });
}
