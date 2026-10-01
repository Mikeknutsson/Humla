import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { KpiApp } from "../_components/kpi-app";

export const dynamic = "force-dynamic";

function ymd(d:Date){return d.toISOString().slice(0,10)}
function overviewPeriods(month=9,day=1){const now=new Date();const yesterday=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),now.getUTCDate()-1));const currentStartCandidate=new Date(Date.UTC(yesterday.getUTCFullYear(),month-1,day));const sy=yesterday<currentStartCandidate?yesterday.getUTCFullYear()-1:yesterday.getUTCFullYear();const currentFrom=new Date(Date.UTC(sy,month-1,day));const previousFrom=new Date(Date.UTC(sy-1,month-1,day));const elapsed=Math.round((yesterday.getTime()-currentFrom.getTime())/86400000);const previousTo=new Date(previousFrom.getTime()+elapsed*86400000);return{current:{from:ymd(currentFrom),to:ymd(yesterday)},previous:{from:ymd(previousFrom),to:ymd(previousTo)},label:`${sy}/${String(sy+1).slice(-2)}`}}
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
  const initialView = query.view === "kpi" || query.view === "import" || query.view === "definitions" || query.view === "accounts" || query.view === "units" || query.view === "review" || (query.view === "transpa" && canManage) ? query.view : "overview";
  const overviewPeriod = overviewPeriods(settings?.financial_year_start_month ?? 9, settings?.financial_year_start_day ?? 1);
  const from = /^\d{4}-\d{2}-\d{2}$/.test(query.from ?? "") ? query.from! : fallback.from;
  const to = /^\d{4}-\d{2}-\d{2}$/.test(query.to ?? "") ? query.to! : fallback.to;

  const [{ data: dashboard, error: dashboardError }, { data: batches, error: batchesError }, { data: accountMappings, error: mappingsError }] = await Promise.all([
    supabase.rpc("hub_kpi_dashboard_display_v1", { p_tenant_id: member.tenant_id, p_from: from, p_to: to }),
    supabase.from("kpi_import_batches").select("id,data_kind,file_name,status,row_count,valid_row_count,invalid_row_count,period_start,period_end,created_at,column_mapping,error_summary").eq("tenant_id", member.tenant_id).order("created_at", { ascending: false }).limit(12),
    supabase.from("kpi_account_mappings").select("id,account_from,account_to,name,calculation_role,cost_category,include_in_vehicle_result,priority,valid_from,valid_to,enabled,notes,created_at,updated_at").eq("tenant_id", member.tenant_id).order("enabled", { ascending: false }).order("account_from"),
  ]);
  const transpaVehicleTime=dashboard?.transpa_vehicle_time??null;
  const efficiency=dashboard?.efficiency??null;
  const hiredCapacity=dashboard?.hired_capacity??null;
  const driverProductivity=dashboard?.driver_productivity??null;

  const displayDashboard = dashboard ?? { metrics: {}, components: {}, vehicles: [], drivers: [], cost_categories: {}, unmapped_accounts: [], quality: {} };
  const {data:overviewWeekly,error:overviewWeeklyError}=initialView==='overview' ? await supabase.rpc("kpi_overview_weekly_v1",{p_tenant_id:member.tenant_id,p_from:from,p_to:to}) : {data:null,error:null};
  const [{data:units,error:unitsError},{data:unitReport,error:unitReportError}] = initialView === 'units' ? await Promise.all([
    supabase.from('kpi_units').select('id,name,unit_type,projects,registrations,employees,valid_from,valid_to,enabled,revision').eq('tenant_id',member.tenant_id).in('origin',['manual','manual_builder']).order('name'),
    supabase.rpc('hub_kpi_unit_report_v2',{p_tenant_id:member.tenant_id,p_from:from,p_to:to}),
  ]) : [{data:[],error:null},{data:null,error:null}];
  const {data:hubReviews,error:hubReviewError}=initialView==='review' ? await supabase.from('hub_review_queue').select('id,review_type,activity_kind,confidence,proposed_matches,payload,reason_code').eq('tenant_id',member.tenant_id).eq('status','open').order('created_at',{ascending:false}).limit(250) : {data:[],error:null};
  const {data:transpaEvidence,error:transpaError}=initialView==='transpa'&&canManage ? await supabase.rpc('kpi_transpa_evidence',{p_tenant_id:member.tenant_id,p_from:from,p_to:to}) : {data:null,error:null};
  const serverIssues = [readError, manageError, dashboardError, batchesError, mappingsError, unitsError, unitReportError, transpaError, hubReviewError, overviewWeeklyError].filter(Boolean).map((error) => error!.message);
  if (serverIssues.length) console.error("[kpi] data lookup failed", { codes: [readError, manageError, dashboardError, batchesError, mappingsError].filter(Boolean).map((error) => error!.code) });
  return <><section style={{padding:"16px 22px",background:"#f5f5f5",borderBottom:"1px solid #ddd"}}>
    <a href={`/kpi/analys?from=${from}&to=${to}`}>Transport → verksamhetsgrupp → enhet → projekt → transaktion</a> · <a href={`/kpi/analys?from=${from}&to=${to}&source=NEXT`}>NEXT-kostnader</a> · <a href={`/kpi/reparationskostnader?from=${from}&to=${to}`}>Reparationsgranskning</a>
    <p>Reparationsgranskning: {new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK"}).format(displayDashboard.repair_summary?.approved??0)} granskade · {new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK"}).format(displayDashboard.repair_summary?.pending??0)} väntar. Separat uppföljning.</p><p>Hub v4 · {displayDashboard.reconciliation?.matches ? "Detaljrader och huvudtotaler avstämda" : "Avstämning saknas – kontrollera underlaget"} · {displayDashboard.personnel_basis}</p>
  </section><KpiApp
    overviewPrevious={(displayDashboard.previous ?? null) as never}
    overviewPeriod={{...overviewPeriod,current:{from,to},previous:{from:`${Number(from.slice(0,4))-1}${from.slice(4)}`,to:`${Number(to.slice(0,4))-1}${to.slice(4)}`},label:from.slice(0,4)}}
    overviewWeekly={(overviewWeekly ?? {weeks:[]}) as never}
    dashboard={displayDashboard}
    batches={(batches ?? []) as never[]}
    tenantName={tenant?.name ?? "Humla"}
    userName={member.display_name ?? user.email ?? "Användare"}
    from={from}
    to={to}
    canManage={Boolean(canManage)}
    accountMappings={(accountMappings ?? []) as never[]}
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
  /></>;
}
