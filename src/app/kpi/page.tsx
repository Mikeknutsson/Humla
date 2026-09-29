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

export default async function Home({ searchParams }: { searchParams: Promise<{ from?: string; to?: string; view?: string; auth_retry?: string }> }) {
  const supabase = await createClient();
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (!user) redirect("/kpi/login");

  const query = await searchParams;
  const { data: member, error: memberError } = await supabase.from("hub_tenant_members").select("tenant_id,display_name,role").eq("user_id", user.id).eq("status", "active").limit(1).maybeSingle();
  if (!member) {
    console.error("[kpi] workspace lookup failed", { auth: authError?.code, member: memberError?.code });
    if (query.auth_retry !== "1") redirect("/kpi?auth_retry=1");
    return <main className="access-denied"><div><span>!</span><h1>Din session fungerar, men KPI-arbetsytan kunde inte öppnas</h1><p>Ingen aktiv KPI-arbetsyta kunde läsas för användaren.</p><a className="primary" href="/kpi/login?stay=1">Hantera KPI-sessionen</a></div></main>;
  }
  const { data: tenant } = await supabase.from("hub_tenants").select("name").eq("id", member.tenant_id).maybeSingle();
  const { data: canRead, error: readError } = await supabase.rpc("hub_has_permission", { p_tenant_id: member.tenant_id, p_permission: "kpi.read" });
  if (!canRead) return <main className="access-denied"><div><span>403</span><h1>Du saknar åtkomst till KPI-appen</h1><p>Be en administratör aktivera din KPI-behörighet.</p></div></main>;
  const { data: canManage, error: manageError } = await supabase.rpc("hub_has_permission", { p_tenant_id: member.tenant_id, p_permission: "kpi.manage" });
  const { data: settings } = await supabase.from("kpi_settings").select("financial_year_start_month,financial_year_start_day").eq("tenant_id", member.tenant_id).maybeSingle();
  const fallback = fiscalPeriod(settings?.financial_year_start_month ?? 9, settings?.financial_year_start_day ?? 1);
  const from = /^\d{4}-\d{2}-\d{2}$/.test(query.from ?? "") ? query.from! : fallback.from;
  const to = /^\d{4}-\d{2}-\d{2}$/.test(query.to ?? "") ? query.to! : fallback.to;

  const [{ data: dashboard, error: dashboardError }, { data: batches, error: batchesError }, { data: accountMappings, error: mappingsError }] = await Promise.all([
    supabase.rpc("kpi_transport_dashboard", { p_tenant_id: member.tenant_id, p_from: from, p_to: to }),
    supabase.from("kpi_import_batches").select("id,data_kind,file_name,status,row_count,valid_row_count,invalid_row_count,period_start,period_end,created_at").eq("tenant_id", member.tenant_id).order("created_at", { ascending: false }).limit(12),
    supabase.from("kpi_account_mappings").select("id,account_from,account_to,name,calculation_role,cost_category,include_in_vehicle_result,priority,valid_from,valid_to,enabled,notes,created_at,updated_at").eq("tenant_id", member.tenant_id).order("enabled", { ascending: false }).order("account_from"),
  ]);

  const emptyDashboard = { metrics: {}, components: {}, vehicles: [], drivers: [], cost_categories: {}, unmapped_accounts: [], quality: {} };
  const initialView = query.view === "import" || query.view === "definitions" || query.view === "accounts" ? query.view : "overview";
  const serverIssues = [readError, manageError, dashboardError, batchesError, mappingsError].filter(Boolean).map((error) => error!.message);
  if (serverIssues.length) console.error("[kpi] data lookup failed", { codes: [readError, manageError, dashboardError, batchesError, mappingsError].filter(Boolean).map((error) => error!.code) });
  return <KpiApp
    dashboard={(dashboard ?? emptyDashboard) as typeof emptyDashboard}
    batches={(batches ?? []) as never[]}
    tenantName={tenant?.name ?? "Humla"}
    userName={member.display_name ?? user.email ?? "Användare"}
    from={from}
    to={to}
    canManage={Boolean(canManage)}
    accountMappings={(accountMappings ?? []) as never[]}
    initialView={initialView}
    serverIssues={serverIssues}
  />;
}
