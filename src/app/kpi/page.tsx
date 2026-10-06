import { redirect } from "next/navigation";
import {cachedKpiReport} from "@/lib/kpi/report-cache";
import { createClient } from "@/lib/supabase/server";
import { parseMonthPeriod, monthPeriodFromDates } from "@/lib/kpi/period";
import { filterKeys } from "@/lib/kpi/analysis";
import { KpiLiveReport } from "../_components/kpi-live-report";

export const dynamic = "force-dynamic";

function fiscalPeriod(month = 9, day = 1) {
  const now = new Date();
  const currentStart = new Date(Date.UTC(now.getUTCFullYear(), month - 1, day));
  const startYear = now < currentStart ? now.getUTCFullYear() - 1 : now.getUTCFullYear();
  const start = new Date(Date.UTC(startYear, month - 1, day));
  const end = new Date(Date.UTC(startYear + 1, month - 1, day - 1));
  return { from: start.toISOString().slice(0, 10), to: end.toISOString().slice(0, 10) };
}

export default async function Home({ searchParams }: { searchParams: Promise<{ from?: string; to?: string; view?: string; cost_center?: string; fiscal_year?: string; months?: string; group?:string; unit?:string; vehicle?:string; project?:string; category?:string; kind?:string; source?:string; date_from?:string; date_to?:string; auth_retry?: string }> }) {
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
  const [{ data: tenant }, { data: canRead, error: readError }, { data: canManage, error: manageError }, { data: settings }] = await Promise.all([
    supabase.from("hub_tenants").select("name").eq("id", member.tenant_id).maybeSingle(),
    supabase.rpc("hub_has_permission", { p_tenant_id: member.tenant_id, p_permission: "kpi.read" }),
    supabase.rpc("hub_has_permission", { p_tenant_id: member.tenant_id, p_permission: "kpi.manage" }),
    supabase.from("kpi_settings").select("financial_year_start_month,financial_year_start_day").eq("tenant_id", member.tenant_id).maybeSingle(),
  ]);
  if (!canRead) return <main className="access-denied"><div><span>403</span><h1>Du saknar åtkomst till KPI-appen</h1><p>Be en administratör aktivera din KPI-behörighet.</p></div></main>;
  const fallback = fiscalPeriod(settings?.financial_year_start_month ?? 9, settings?.financial_year_start_day ?? 1);
  const initialView = query.view === "monthly" || query.view === "internal" || query.view === "kpi" || query.view === "import" || query.view === "definitions" || query.view === "accounts" || query.view === "units" || query.view === "review" || (query.view === "transpa" && canManage) ? query.view : "overview";
  const legacyMonths = monthPeriodFromDates(query.from,query.to);
  const useMonths = initialView === "overview" || initialView === "monthly" || query.months !== undefined || query.fiscal_year !== undefined || Boolean(legacyMonths) || ((initialView === "kpi" || initialView === "internal") && !query.from && !query.to);
  let monthPeriod;
  try { monthPeriod = query.fiscal_year === undefined && query.months === undefined && legacyMonths ? legacyMonths : parseMonthPeriod(query.fiscal_year,query.months); } catch { return <main className="content"><h1>Ogiltigt månadsurval</h1><a href="/kpi">Återställ till hela verksamhetsåret</a></main>; }
  const activeFilters = Object.fromEntries(filterKeys.filter(k=>query[k]).map(k=>[k,query[k]!]));
  const from = useMonths ? `${monthPeriod.fiscalYear}-09-01` : /^\d{4}-\d{2}-\d{2}$/.test(query.from ?? "") ? query.from! : fallback.from;
  const costCenter = query.cost_center?.trim() || null;
  const to = useMonths ? `${monthPeriod.fiscalYear+1}-08-31` : /^\d{4}-\d{2}-\d{2}$/.test(query.to ?? "") ? query.to! : fallback.to;

  const needsReport = initialView === "overview" || initialView === "kpi";
  const needsBatches = needsReport || initialView === "import";
  const [{ data: dashboard, error: dashboardError }, { data: batches, error: batchesError }] = await Promise.all([
    needsReport ? cachedKpiReport(user.id,member.tenant_id,{useMonths,monthPeriod,costCenter,activeFilters,from,to},async()=>useMonths ? supabase.rpc("hub_kpi_overview_months_v1", { p_tenant_id:member.tenant_id, p_fiscal_year:monthPeriod.fiscalYear,p_selected_months:monthPeriod.months,p_cost_center:costCenter,p_filters:activeFilters }) : supabase.rpc("hub_kpi_cost_center_dashboard_v1", { p_tenant_id: member.tenant_id, p_from: from, p_to: to, p_cost_center: costCenter })) : Promise.resolve({ data: null, error: null }),
    needsBatches ? supabase.from("kpi_import_batches").select("id,data_kind,file_name,status,row_count,valid_row_count,invalid_row_count,period_start,period_end,created_at,column_mapping,error_summary,provenance").eq("tenant_id", member.tenant_id).order("created_at", { ascending: false }).limit(12) : Promise.resolve({ data: [], error: null }),
  ]);
  if ((initialView === "overview" || initialView === "kpi") && (dashboardError || !dashboard)) {
    console.error("[kpi] financial report unavailable", { code: dashboardError?.code });
    const retryQuery = new URLSearchParams(Object.entries(query).filter((entry): entry is [string, string] => typeof entry[1] === "string"));
    return <main className="access-denied"><div role="alert"><h1>Rapporten kunde inte hämtas</h1><p>Hubben kunde inte lämna ett verifierat resultat för urvalet. Inga KPI-belopp visas eftersom saknade data inte är samma sak som noll.</p><a className="primary" href={`/kpi?${retryQuery.toString()}`}>Försök igen med samma urval</a></div></main>;
  }
  const transpaVehicleTime=dashboard?.transpa_vehicle_time??null;
  const efficiency=dashboard?.efficiency??null;
  const hiredCapacity=dashboard?.hired_capacity??null;
  const driverProductivity=dashboard?.driver_productivity??null;

  const displayDashboard = dashboard ?? { cost_center_scope: costCenter, metrics: {}, components: {}, vehicles: [], drivers: [], cost_categories: {}, unmapped_accounts: [], quality: {} };
  const [{data:units,error:unitsError},{data:unitReport,error:unitReportError}] = initialView === 'units' ? await Promise.all([
    supabase.from('kpi_units').select('id,name,unit_type,projects,registrations,employees,valid_from,valid_to,enabled,revision').eq('tenant_id',member.tenant_id).in('origin',['manual','manual_builder']).order('name'),
    supabase.rpc('hub_kpi_unit_report_v2',{p_tenant_id:member.tenant_id,p_from:from,p_to:to}),
  ]) : [{data:[],error:null},{data:null,error:null}];
  const {data:hubReviews,error:hubReviewError}=initialView==='review' ? await supabase.from('hub_review_queue').select('id,review_type,activity_kind,confidence,proposed_matches,payload,reason_code').eq('tenant_id',member.tenant_id).eq('status','open').order('created_at',{ascending:false}).limit(250) : {data:[],error:null};
  const {data:transpaEvidence,error:transpaError}=initialView==='transpa'&&canManage ? await supabase.rpc('kpi_transpa_evidence',{p_tenant_id:member.tenant_id,p_from:from,p_to:to}) : {data:null,error:null};
  const serverIssues = [readError, manageError, dashboardError, batchesError, unitsError, unitReportError, transpaError, hubReviewError].filter(Boolean).map((error) => error!.message);
  if (serverIssues.length) console.error("[kpi] data lookup failed", { codes: [readError, manageError, dashboardError, batchesError].filter(Boolean).map((error) => error!.code) });
  return <KpiLiveReport key={initialView}
    monthPeriod={useMonths?monthPeriod:undefined}
    overviewMonthly={(displayDashboard.monthly??[]) as never}
    activeFilters={activeFilters}
    overviewPrevious={(displayDashboard.previous ?? null) as never}
    overviewPeriod={{current:{from,to},previous:{from:`${Number(from.slice(0,4))-1}${from.slice(4)}`,to:`${Number(to.slice(0,4))-1}${to.slice(4)}`},label:`${monthPeriod.fiscalYear}/${monthPeriod.fiscalYear+1}`}}
    dashboard={displayDashboard}
    batches={(batches ?? []) as never[]}
    tenantName={tenant?.name ?? "Humla"}
    userName={member.display_name ?? user.email ?? "Användare"}
    from={from}
    to={to}
    canManage={Boolean(canManage)}
    units={(units ?? []) as never[]}
    unitReport={unitReport ?? {units:[],quality:{},conflict_rows:[]}}
    transpaEvidence={transpaEvidence}
    transpaVehicleTime={transpaVehicleTime}
    efficiency={efficiency}
    hiredCapacity={hiredCapacity}
    driverProductivity={driverProductivity}
    hubReviews={(hubReviews ?? []) as never[]}
    initialView={initialView}
    serverIssues={serverIssues}
  />;
}
