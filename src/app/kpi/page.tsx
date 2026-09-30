import { redirect } from "next/navigation";
import { cookies } from "next/headers";
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
  const cookieStore = await cookies();
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

  const [{ data: dashboard, error: dashboardError }, { data: batches, error: batchesError }, { data: accountMappings, error: mappingsError }, { data: transpaVehicleTime, error: transpaVehicleTimeError }, { data: efficiency, error: efficiencyError }, { data: hiredCapacity, error: hiredCapacityError }, { data: driverProductivity, error: driverProductivityError }] = await Promise.all([
    supabase.rpc("hub_kpi_transport_dashboard_v4", { p_tenant_id: member.tenant_id, p_from: from, p_to: to }),
    supabase.from("kpi_import_batches").select("id,data_kind,file_name,status,row_count,valid_row_count,invalid_row_count,period_start,period_end,created_at,column_mapping,error_summary").eq("tenant_id", member.tenant_id).order("created_at", { ascending: false }).limit(12),
    supabase.from("kpi_account_mappings").select("id,account_from,account_to,name,calculation_role,cost_category,include_in_vehicle_result,priority,valid_from,valid_to,enabled,notes,created_at,updated_at").eq("tenant_id", member.tenant_id).order("enabled", { ascending: false }).order("account_from"),
    supabase.rpc("kpi_transpa_vehicle_time", { p_tenant_id: member.tenant_id, p_from: from, p_to: to }),
    supabase.rpc("kpi_transport_efficiency", { p_tenant_id: member.tenant_id, p_from: from, p_to: to }),
    supabase.rpc("kpi_hired_capacity_share", { p_tenant_id: member.tenant_id, p_from: from, p_to: to }),
    supabase.rpc("kpi_driver_productive_time", { p_tenant_id: member.tenant_id, p_from: from, p_to: to }),
  ]);

  // NEXT repair costs are displayed separately until accounting mappings and
  // vehicle allocations are verified; do not add these totals to KPI result.
  const {data:repairRows,error:repairError}=await supabase.from("hub_fordonskontrollen_cost_outbox")
    .select("status,amount").eq("tenant_id",member.tenant_id)
    .gte("occurred_on",from).lte("occurred_on",to).limit(10000);
  const repairTotals=(repairRows??[]).reduce((acc,row)=>{
    if(row.status==="approved"){acc.approved+=Number(row.amount??0);acc.approvedCount++;}
    if(row.status==="pending_review"){acc.pending+=Number(row.amount??0);acc.pendingCount++;}
    return acc;
  },{approved:0,pending:0,approvedCount:0,pendingCount:0});
  const sek=(n:number)=>new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK",maximumFractionDigits:0}).format(n);

  // Humla Hub owns NEXT cost allocation. KPI only consumes the calculated result.
  const {data:nextCostHub,error:nextCostHubError}=await supabase.rpc("hub_kpi_next_vehicle_costs_v1",{p_tenant_id:member.tenant_id,p_from:from,p_to:to});
  const nextCostError=nextCostHubError?.message??"";
  const hubVehicleCosts=Array.isArray(nextCostHub?.vehicles)?nextCostHub.vehicles as Array<{vehicle?:string;cost?:number|string;fuel_cost?:number|string}>:[];
  const byVehicle=new Map(hubVehicleCosts.map(row=>[String(row.vehicle??"").trim().toUpperCase(),Number(row.cost??0)]));
  const fuelByVehicle=new Map(hubVehicleCosts.map(row=>[String(row.vehicle??"").trim().toUpperCase(),Number(row.fuel_cost??0)]));
  const mappedNextCost=Number(nextCostHub?.mapped_other_cost??0);
  const mappedFuelCost=Number(nextCostHub?.mapped_fuel_cost??0);
  const unallocatedNextCost=Number(nextCostHub?.unallocated_cost??0);
  // Dashboard previously had no account mappings and displayed zero costs.
  // The overlay is provisional; do not add it again once mapped KPI costs exist.
  const hubDashboard=(dashboard??{metrics:{},components:{},cost_categories:[],revenue_categories:[]}) as unknown as { cost_categories?:Array<{category:string;amount:number|string}>; revenue_categories?:Array<Record<string,number|string>>; metrics:Record<string,number|string>;components:Record<string,number|string>; };\n  const { data: legacyDashboard } = await supabase.rpc("kpi_transport_dashboard", { p_tenant_id: member.tenant_id, p_from: from, p_to: to });\n  const baseDashboard=(legacyDashboard??{metrics:{},components:{},vehicles:[],drivers:[],cost_categories:{},unmapped_accounts:[],quality:{}}) as {
    metrics:Record<string,number|string>;components:Record<string,number|string>;
    vehicles:Array<Record<string,number|string>>;drivers:Array<Record<string,number|string>>;
    cost_categories:Record<string,number|string>;unmapped_accounts:Array<{account:string;description?:string|null;row_count:number;amount:number}>;quality:Record<string,number|string>;
  };
  const hubCostCategories: Record<string, number> = Object.fromEntries((hubDashboard.cost_categories??[]).map(row=>[String(row.category),Number(row.amount??0)]));
  const transpaPersonnel=Number(hubDashboard.components?.transpa_personnel_cost??0);
  hubCostCategories.personnel=Number(hubCostCategories.personnel??0)+transpaPersonnel;
  const displayDashboard={
    ...baseDashboard,
    metrics:{...baseDashboard.metrics,...hubDashboard.metrics},
    components:{...baseDashboard.components,...hubDashboard.components,fuel_cost:Number(hubCostCategories.fuel??0),other_cost:Number(hubDashboard.metrics?.total_cost??0)},
    cost_categories:hubCostCategories
  };
  const emptyDashboard = { metrics: {}, components: {}, vehicles: [], drivers: [], cost_categories: {}, unmapped_accounts: [], quality: {} };

  const {data:overviewWeekly,error:overviewWeeklyError}=initialView==='overview' ? await supabase.rpc("kpi_overview_weekly_v1",{p_tenant_id:member.tenant_id,p_from:overviewPeriod.current.from,p_to:overviewPeriod.current.to}) : {data:null,error:null};
  const {data:previousDashboard,error:previousDashboardError}=initialView==='overview' ? await supabase.rpc("kpi_transport_dashboard",{p_tenant_id:member.tenant_id,p_from:overviewPeriod.previous.from,p_to:overviewPeriod.previous.to}) : {data:null,error:null};
  const [{data:units,error:unitsError},{data:unitReport,error:unitReportError}] = initialView === 'units' ? await Promise.all([
    supabase.from('kpi_units').select('id,name,unit_type,projects,registrations,employees,valid_from,valid_to,enabled,revision').eq('tenant_id',member.tenant_id).eq('origin','manual').order('name'),
    supabase.rpc('kpi_unit_report',{p_tenant_id:member.tenant_id,p_from:from,p_to:to}),
  ]) : [{data:[],error:null},{data:null,error:null}];
  const {data:hubReviews,error:hubReviewError}=initialView==='review' ? await supabase.from('hub_review_queue').select('id,review_type,activity_kind,confidence,proposed_matches,payload,reason_code').eq('tenant_id',member.tenant_id).eq('status','open').order('created_at',{ascending:false}).limit(250) : {data:[],error:null};
  const {data:transpaEvidence,error:transpaError}=initialView==='transpa'&&canManage ? await supabase.rpc('kpi_transpa_evidence',{p_tenant_id:member.tenant_id,p_from:from,p_to:to}) : {data:null,error:null};
  const serverIssues = [readError, manageError, dashboardError, batchesError, mappingsError, unitsError, unitReportError, transpaError, transpaVehicleTimeError, efficiencyError, hiredCapacityError, driverProductivityError, hubReviewError, previousDashboardError, overviewWeeklyError, repairError, nextCostHubError].filter(Boolean).map((error) => error!.message);
  if (serverIssues.length) console.error("[kpi] data lookup failed", { codes: [readError, manageError, dashboardError, batchesError, mappingsError].filter(Boolean).map((error) => error!.code) });
  return <><section style={{padding:"16px 22px",background:"#f5f5f5",borderBottom:"1px solid #ddd"}}><div style={{marginBottom:10}}>{nextCostError?`NEXT-kostnader kunde inte fördelas: ${nextCostError}`:`NEXT: ${sek(mappedNextCost)} preliminärt fördelat på fordon; ${sek(unallocatedNextCost)} återstår att granska. Interna överföringar ingår inte.`}</div><div style={{marginBottom:10}}><a style={{fontWeight:700}} href={`/kpi/next-kostnader?from=${from}&to=${to}`}>Alla kostnader från NEXT – fördelning per fordon och konto →</a></div>
    <div style={{display:"flex",gap:24,alignItems:"center",flexWrap:"wrap"}}>
      <div><strong>Reparationskostnader från NEXT</strong><div style={{fontSize:12}}>Separat uppföljning – inte dubbelräknade i resultatet</div></div>
      <div><div style={{fontSize:12}}>Granskade för möjlig export</div><strong>{repairError?"Kunde inte läsas":sek(repairTotals.approved)}</strong><div style={{fontSize:12}}>{repairTotals.approvedCount} poster</div></div>
      <div><div style={{fontSize:12}}>Väntar på granskning</div><strong>{repairError?"Kunde inte läsas":sek(repairTotals.pending)}</strong><div style={{fontSize:12}}>{repairTotals.pendingCount} poster</div></div>
      <a style={{fontWeight:600}} href={`/kpi/reparationskostnader?from=${from}&to=${to}`}>Visa fördelning och detaljer →</a>
    </div>
  </section><KpiApp
    overviewPrevious={(previousDashboard ?? null) as never}
    overviewPeriod={overviewPeriod}
    overviewWeekly={(overviewWeekly ?? {weeks:[]}) as never}
    dashboard={displayDashboard as typeof emptyDashboard}
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
