import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { KpiApp } from "../_components/kpi-app";

export const dynamic = "force-dynamic";

function fiscalPeriod(month = 9, day = 1) {
  const now = new Date();
  const currentStart = new Date(Date.UTC(now.getUTCFullYear(), month - 1, day));
  const startYear = now < currentStart ? now.getUTCFullYear() - 1 : now.getUTCFullYear();
  const start = new Date(Date.UTC(startYear, month - 1, day));
  const end = new Date(Date.UTC(startYear + 1, month - 1, day - 1));
  return { from: start.toISOString().slice(0, 10), to: end.toISOString().slice(0, 10) };
}

export default async function Home({ searchParams }: { searchParams: Promise<{ from?: string; to?: string }> }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/kpi/login");

  const { data: member } = await supabase.from("hub_tenant_members").select("tenant_id,display_name,role,hub_tenants(name)").eq("user_id", user.id).eq("status", "active").maybeSingle();
  if (!member) redirect("/kpi/login?error=Du saknar en aktiv Humla-arbetsyta.");
  const tenant = Array.isArray(member.hub_tenants) ? member.hub_tenants[0] : member.hub_tenants;
  const { data: canRead } = await supabase.rpc("hub_has_permission", { p_tenant_id: member.tenant_id, p_permission: "kpi.read" });
  if (!canRead) return <main className="access-denied"><div><span>403</span><h1>Du saknar åtkomst till Humla KPI</h1><p>Be en administratör tilldela behörigheten <code>kpi.read</code>.</p></div></main>;
  const { data: canManage } = await supabase.rpc("hub_has_permission", { p_tenant_id: member.tenant_id, p_permission: "kpi.manage" });
  const { data: settings } = await supabase.from("kpi_settings").select("financial_year_start_month,financial_year_start_day").eq("tenant_id", member.tenant_id).maybeSingle();
  const fallback = fiscalPeriod(settings?.financial_year_start_month ?? 9, settings?.financial_year_start_day ?? 1);
  const query = await searchParams;
  const from = /^\d{4}-\d{2}-\d{2}$/.test(query.from ?? "") ? query.from! : fallback.from;
  const to = /^\d{4}-\d{2}-\d{2}$/.test(query.to ?? "") ? query.to! : fallback.to;

  const [{ data: dashboard }, { data: batches }] = await Promise.all([
    supabase.rpc("kpi_transport_dashboard", { p_tenant_id: member.tenant_id, p_from: from, p_to: to }),
    supabase.from("kpi_import_batches").select("id,data_kind,file_name,status,row_count,valid_row_count,invalid_row_count,period_start,period_end,created_at").eq("tenant_id", member.tenant_id).order("created_at", { ascending: false }).limit(12),
  ]);

  const emptyDashboard = { metrics: {}, components: {}, vehicles: [], drivers: [], quality: {} };
  return <KpiApp
    dashboard={(dashboard ?? emptyDashboard) as typeof emptyDashboard}
    batches={(batches ?? []) as never[]}
    tenantName={tenant?.name ?? "Humla"}
    userName={member.display_name ?? user.email ?? "Användare"}
    from={from}
    to={to}
    canManage={Boolean(canManage)}
  />;
}
