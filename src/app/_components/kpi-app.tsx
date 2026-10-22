"use client";
import {useKpiInternalSummary} from './use-kpi-internal-summary';
import {InternalYearChange,useInternalYearComparison} from './internal-year-change';
import {KpiOverhead} from './kpi-overhead';
import {KpiBillingBalance} from './kpi-billing-balance';
import {KpiMaterialProject} from './kpi-material-project';
import {KpiYearComparison} from './kpi-year-comparison';
import type {OverheadKpi} from '@/lib/kpi/overhead';
import {KpiCostCenterFilter} from './kpi-cost-center-filter';
import {WorkshopTimeKpi} from './workshop-time-kpi';

import { KpiCostBreakdown } from "./kpi-cost-breakdown";
import {KpiWorkspace,KpiSidebarToggle} from './kpi-workspace';
import workspaceStyles from './kpi-workspace.module.css';
import { KpiMonthPeriod } from "./kpi-month-period";
import {KpiPrint} from './kpi-print';
import {KpiEconomicUnits,type EconomicUnit} from './kpi-economic-units';
import { KpiMonthChart, type MonthlyPoint } from "./kpi-month-chart";
import { monthPeriodQuery,type MonthPeriod } from "@/lib/kpi/period";
import dynamic from "next/dynamic";
const ImportReview = dynamic(() => import("./import-review").then(m => m.ImportReview));
const HubReview = dynamic(() => import("./hub-review").then(m => m.HubReview));
const WorkifyNameRules = dynamic(() => import("./workify-name-rules").then(m => m.WorkifyNameRules));
const KpiReviewQueue = dynamic(() => import("./kpi-review-queue").then(m => m.KpiReviewQueue));

import Link from "next/link";
import {useSearchParams} from "next/navigation";
import {InternalTransfers} from './internal-transfers';
const KpiMonthlyReport = dynamic(() => import('./kpi-monthly-report').then(m => m.KpiMonthlyReport));
import {selectionFromQuery} from '@/lib/kpi/selection';
import {analysisHref} from "@/lib/kpi/analysis";
import { useEffect, useMemo, useState } from "react";
import {
  BarChart3, CheckCircle2, ChevronRight, Database, FileSpreadsheet, Fuel,
  Gauge, LayoutDashboard, ListTree, Menu, RefreshCw, Settings2, ShieldCheck, Truck,
  UploadCloud, Users, WalletCards, X, AlertTriangle,
} from "lucide-react";
import { DATA_KINDS, suggestMapping, type DataKind, type ParsedRow } from "@/lib/kpi/schema";
import { parseVehicleRules, resolveVehicle } from "@/lib/kpi/vehicle-rules";
import { logout } from "../kpi/login/actions";
import type { AccountMapping } from "@/lib/kpi/account-mapping";
import type {TranspaEvidence} from './transpa-evidence';
const TranspaEvidencePanel = dynamic(() => import('./transpa-evidence').then(m => m.TranspaEvidencePanel));
const CompoundUnitBuilder = dynamic(() => import('./compound-unit-builder').then(m => m.CompoundUnitBuilder));
const UnitManager = dynamic(() => import('./unit-manager').then(m => m.UnitManager));
import type {KpiUnit,UnitReport} from '@/lib/kpi/units';

type DriverAttendance={status:string;attendance_percent:number|null;sick_percent:number|null;vab_percent:number|null;vacation_percent:number|null;other_absence_percent:number|null;basis:string};
type InternalSummary={status?:string;material_margin?:{billed:number|null;purchase_cost:number|null;difference:number|null;margin_percent:number|null;rows:number;fallback_rows:number;fallback_billed:number;fallback_purchase:number;bundled_billed:number;details:{source_row:string;date:string;order_number:string|null;article:string|null;billed:number;purchase_cost:number|null;difference:number|null;fallback:boolean;bundled:boolean;evidence:{status?:string;rate?:number;quantity?:number;unit?:string;price_source?:string;note?:string}}[];matched_rows:number;estimated_rows:number;missing_rows:number;missing_billed:number;bundled_rows:number;bundled_material_component:number;basis:string};remaining?:number|null;remaining_percent?:number|null;total_percent:number|null;material_percent:number|null;tipp_deponi_percent:number|null;revenue_basis:number|null;total:number|null;material:number|null;tipp_deponi:number|null;transport:number|null;rows:number;review_rows:number;review_amount:number;review_included?:boolean;pending_rows?:number;pending_amount?:number;basis:string};
export type Dashboard = {
 material_unit_id?:string|null;
 excluded_projects?:Array<{project_id:string;name:string;reason:string}>;
 overhead?:OverheadKpi;
  internal_summary?:InternalSummary;
  driver_attendance?:DriverAttendance;
  invoice_lead_time?: {average_days:number|null;order_days:number;averaged_orders?:number;internal_average_days?:number|null;internal_averaged_orders?:number;zero_order_days?:number;orders:number;invalid_order_days:number};
  material_separation?: {active:boolean;review_rows:number;split_rows:number};
  group_options?:string[];
  economic_units?:EconomicUnit[];
  comparison_available?:boolean;
  coverage?:{revenue_months:number[];cost_months:number[]};
  unclassified_summary?: Record<string,number|null>;
  unit_assignment_summary?:{rows:number;revenue:number;cost:number};
  cost_centers?: Array<{code:string;name:string}>;
  cost_center_scope?: string|null;
  classification_valid_from?: string;
  scoped_operational_unavailable?: boolean;
  cost_efficiency?: Record<string, number | null>;
  business_groups?: Array<{key:string;label:string;revenue:number;cost:number;result:number}>;
  personnel_basis?: string;
  metrics: Record<string, number | string>;
  components: Record<string, number | string>;
  vehicles: Array<Record<string, number | string>>;
  drivers: Array<Record<string, number | string>>;
  cost_categories: Record<string, number | string>;
  unmapped_accounts: Array<{ account: string; description?: string | null; row_count: number; amount: number }>;
  quality: Record<string, number | string>;
};

type HiredCapacity = { total_revenue?:number; hired_revenue?:number; hired_share_percent?:number; hired_rows?:number; classification?:string; rows?:Array<{id:string;occurred_on:string;vehicle_registration:string;project_reference?:string|null;description?:string|null;amount:number}> };

type Efficiency = { revenue?:number; own_revenue?:number; hired_revenue?:number; worked_hours?:number; revenue_per_worked_hour?:number|null; ballast_cost?:number; tipping_cost?:number; direct_material_tipping_cost?:number; contribution_after_material_tipping?:number; result_per_worked_hour_after_material_tipping?:number|null; cost_data_available?:boolean };

type DriverProductivity = { total_hours?:number; productive_hours?:number; unclassified_hours?:number; productive_percent?:number; definition?:string; drivers?:Array<{employee_id:string;driver:string;total_hours:number;productive_hours:number;unclassified_hours:number;productive_percent:number}> };

type TranspaVehicleTime = { reported_hours?: number; available_hours?: number; utilization?: number; vehicle_count?: number; capacity_hours_per_day?: number; vehicles?: Array<{vehicle_id:string;vehicle:string;occupied_hours:number;available_hours:number;utilization:number;time_reports:number}> };

type Batch = {
  provenance?: {cost_center?:string;workify_import_result?:{insertedRows:number;duplicateRowsSkipped?:number;ignoredZeroRows?:number;changedRows?:number;status:string;changes?:Array<{row:number;order:string;date:string;amount:number;reason:string}>}};
  error_summary?: Array<{ row?: number; errors?: string[]; message?: string }>;
  column_mapping?: Record<string, string>;
  id: string;
  data_kind: DataKind;
  file_name: string | null;
  status: string;
  row_count: number;
  valid_row_count: number;
  invalid_row_count: number;
  period_start: string | null;
  period_end: string | null;
  created_at: string;
};

type Preview = {
  headers: string[];
  rows: ParsedRow[];
  totalRows: number;
  sheetName?: string;
  pageCount?: number;
  suggestedMapping: Record<string, string>;
  detectedKind: DataKind | null;
};

const currency = new Intl.NumberFormat("sv-SE", { style: "currency", currency: "SEK", maximumFractionDigits: 0 });
const number = new Intl.NumberFormat("sv-SE", { maximumFractionDigits: 1 });

function numeric(value: unknown) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function statusLabel(status: string) {
  if (status === "completed") return "Klar";
  if (status === "needs_review") return "Behöver granskas";
  if (status === "failed") return "Misslyckad";
  return "Bearbetas";
}

export type KpiAppProps = {
  internalDefaultPeriod: {from:string;to:string};
  monthPeriod?: MonthPeriod;
  overviewMonthly: MonthlyPoint[];
  activeFilters: Record<string,string>;
  transpaEvidence: TranspaEvidence | null;
  transpaVehicleTime: TranspaVehicleTime | null;
  efficiency: Efficiency | null;
  hiredCapacity: HiredCapacity | null;
  driverProductivity: DriverProductivity | null;
  hubReviews: Array<{id:string;review_type:string;activity_kind?:string;confidence?:number;proposed_matches?:unknown;payload?:unknown;reason_code?:string}>;
  units: KpiUnit[];
  unitReport: UnitReport;
  dashboard: Dashboard;
  overviewPrevious: Dashboard | null;
  overviewPeriod: {current:{from:string;to:string};previous:{from:string;to:string};label:string};
  batches: Batch[];
  accountMappings?: AccountMapping[];
  tenantName: string;
  userName: string;
  from: string;
  to: string;
  canManage: boolean;
  initialView?: "overview" | "kpi" | "import" | "definitions" | "accounts" | "units" | "transpa" | "review" | "internal" | "monthly";
  serverIssues?: string[];
  onPeriodChange?: (query:string)=>Promise<void>;
};

export function KpiApp({ internalDefaultPeriod, monthPeriod, overviewMonthly, activeFilters, dashboard, overviewPrevious, overviewPeriod, batches, units, unitReport, transpaEvidence, transpaVehicleTime, efficiency, hiredCapacity, driverProductivity, hubReviews, tenantName, userName, from, to, canManage, initialView = "kpi", serverIssues = [], onPeriodChange }: KpiAppProps) {
  const liveQuery=useSearchParams();
  const financialView=initialView==='overview'||initialView==='kpi';
  const view=financialView?(liveQuery.get('view')==='overview'?'overview':'kpi'):initialView;
  function switchFinancialView(event:React.MouseEvent<HTMLAnchorElement>) {
    if(!financialView||event.button!==0||event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;
    event.preventDefault();
    window.history.pushState(null,'',event.currentTarget.href);
    setMobileMenu(false);
  }
  const [mobileMenu, setMobileMenu] = useState(false);
  const [dataKind, setDataKind] = useState<DataKind>("revenue");
  const [automatic, setAutomatic] = useState(true);
  const [kindConfirmed, setKindConfirmed] = useState(false);
  const [pendingFiles, setPendingFiles] = useState<File[]>([]);
  const [vehicleRules, setVehicleRules] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [mapping, setMapping] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ type: "error" | "success"; text: string } | null>(null);

  useEffect(() => { if(view==='internal')return; localStorage.setItem("humla:kpi:period", JSON.stringify({ from, to })); document.cookie = `humla_kpi_from=${from}; Path=/; Max-Age=31536000; SameSite=Lax`; document.cookie = `humla_kpi_to=${to}; Path=/; Max-Age=31536000; SameSite=Lax`; }, [from, to, view]);
  const scopedOperationsUnavailable = Boolean(dashboard.scoped_operational_unavailable);
  const costCenter = dashboard.cost_center_scope ?? activeFilters.cost_center ?? "";
  const scopeQuery = costCenter ? `&cost_center=${encodeURIComponent(costCenter)}` : "";
  const filterQuery = new URLSearchParams(Object.entries(activeFilters).filter(([k])=>k!=="cost_center")).toString();
  const periodQuery = view==='monthly' ? selectionFromQuery(new URLSearchParams(liveQuery.toString())).toString() : (monthPeriod ? monthPeriodQuery(monthPeriod) : `from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`)+scopeQuery+(filterQuery?`&${filterQuery}`:"");
  const kpiHref = (nextView?: string) => nextView==='internal' ? `/kpi?view=internal&from=${internalDefaultPeriod.from}&to=${internalDefaultPeriod.to}${scopeQuery}` : `/kpi?${nextView ? `view=${nextView}&` : ""}${periodQuery}`;
  const selectedDate = new Date(`${from}T00:00:00Z`); const selectedFiscalStartYear = selectedDate.getUTCMonth() >= 8 ? selectedDate.getUTCFullYear() : selectedDate.getUTCFullYear() - 1; const fiscalYears = Array.from({ length: 4 }, (_, index) => { const startYear = selectedFiscalStartYear - index; const endYear = startYear + 1; return { label: `${startYear}/${endYear}`, from: `${startYear}-09-01`, to: `${endYear}-08-31` }; });

  const metrics = dashboard.metrics ?? {};
  const rows = numeric(dashboard.quality?.total_rows);
  const currentRevenue = numeric(metrics.revenue);
  const previousRevenue = numeric(overviewPrevious?.metrics?.revenue);
  const currentResult = numeric(metrics.result);
  const previousResult = numeric(overviewPrevious?.metrics?.result);
  const revenueChange = metrics.revenue_change_pct == null ? null : numeric(metrics.revenue_change_pct);
  const resultMargin = metrics.margin_pct == null ? null : numeric(metrics.margin_pct);
  const previousMargin = dashboard.comparison_available === false || overviewPrevious?.metrics?.margin_pct == null ? null : numeric(overviewPrevious.metrics.margin_pct);
  const validRows = numeric(dashboard.quality?.valid_rows);
  const pendingBatches = batches.filter(b=>["processing","failed"].includes(b.status) && (!b.period_start || b.period_start<=to) && (!b.period_end || b.period_end>=from) && (!costCenter || !b.provenance?.cost_center || costCenter.split(',').includes(b.provenance.cost_center)));
  const reviewCount = hubReviews.length;
  const costBreakdown = <KpiCostBreakdown values={dashboard.cost_categories ?? {}} total={metrics.total_cost} query={periodQuery} personnelBasis={dashboard.personnel_basis}/>;
  const workedHours = numeric(dashboard.cost_efficiency?.worked_hours);
  const costCards = [
    ["Total kostnad / arbetad timme","total_cost_per_hour"],
    ["Direkt kostnad / arbetad timme","direct_cost_per_hour"],
    ["Gemensamt / arbetad timme","common_cost_per_hour"],
    ["Overhead / arbetad timme","overhead_cost_per_hour"],
    ["Personalkostnad / arbetad timme","personnel_cost_per_hour"],
    ["Bränsle / arbetad timme","fuel_cost_per_hour"],
    ["Service & Rep / arbetad timme","service_repair_cost_per_hour"],
    ["Fasta kostnader / arbetad timme","fixed_cost_per_hour"],
    ["TB / arbetad timme","contribution_per_hour"],
    ["Resultat / arbetad timme","result_per_hour"],
  ].map(([label,key])=>({label,category:({personnel_cost_per_hour:"personnel",fuel_cost_per_hour:"fuel",service_repair_cost_per_hour:"service_repair",fixed_cost_per_hour:"fixed"} as Record<string,string>)[key],value:dashboard.cost_efficiency?.[key] == null ? "–" : currency.format(numeric(dashboard.cost_efficiency[key]))+"/h",detail:dashboard.cost_efficiency?.[key] == null ? "Inväntar verifierat klassificeringsunderlag" : "Beräknat i Humla Hub"}));
  const vehicleCount = numeric(transpaVehicleTime?.vehicle_count);
  const reportedHours = numeric(transpaVehicleTime?.reported_hours);
  const availableHours = numeric(transpaVehicleTime?.available_hours);
  const utilization = transpaVehicleTime?.utilization ?? metrics.vehicle_utilization;
  const hiredShare = hiredCapacity?.hired_share_percent;
  const attendance=dashboard.driver_attendance;
  const internal=useKpiInternalSummary(dashboard.internal_summary,periodQuery,view==='overview'||view==='kpi');
  const internalComparison=useInternalYearComparison(periodQuery,view==='overview');
  const percentDisplay = (value: unknown) => value == null ? "–" : `${number.format(numeric(value))} %`;
  const missingVehicle = numeric(dashboard.quality?.rows_without_vehicle);
  const missingEmployee = numeric(dashboard.quality?.rows_without_employee);
  const unmappedAccounts = numeric(dashboard.quality?.rows_without_account_mapping);
  const attentionItems = [
    reviewCount > 0 ? {label:"Behöver granskas",value:String(reviewCount),detail:"Öppna granskningsfall",href:kpiHref("review")} : null,
    unmappedAccounts > 0 ? {label:"Konton utan klassificering",value:number.format(unmappedAccounts),detail:"Påverkar kostnadsanalysen",href:kpiHref("accounts")} : null,
    missingVehicle > 0 ? {label:"Rader utan fordon",value:number.format(missingVehicle),detail:"Kan inte fördelas på fordonsnivå",href:kpiHref("kpi")} : null,
    missingEmployee > 0 ? {label:"Tid utan personkoppling",value:number.format(missingEmployee),detail:"Påverkar personaluppföljningen",href:kpiHref("kpi")} : null,
  ].filter(Boolean) as Array<{label:string;value:string;detail:string;href:string}>;
  const financeBasis = <section className="panel finance-basis"><div className="panel-head"><div><span className="section-kicker">Ekonomiskt underlag</span><h2>Så räknas intäkter och kostnader</h2></div></div><p>Intäkterna kommer från Workifys artikelrader efter artikeldatum. Alla orderstatusar med giltiga belopp ingår; summan kan därför skilja sig från bokförd eller enbart fakturerad omsättning.</p><div className="mini-kpi-grid"><Link prefetch={false} href={analysisHref(periodQuery,{source:"NEXT",kind:"cost"})}><span>Importerade NEXT-kostnader</span><strong>{currency.format(numeric(dashboard.components.next_total_cost))}</strong><small>Bokförda kostnadsrader efter avstämning av egen tank</small></Link><Link prefetch={false} href={analysisHref(periodQuery,{source:"Piusi",kind:"cost",category:"fuel"})}><span>Piusi-bränsle</span><strong>{currency.format(numeric(dashboard.components.piusi_fuel_cost))}</strong><small>Tankningar · preliminära API-priser eller godkända belopp</small></Link><Link prefetch={false} href={analysisHref(periodQuery,{source:"TransPA",kind:"cost"})}><span>Beräknad personalkostnad</span><strong>{currency.format(numeric(dashboard.components.transpa_personnel_cost))}</strong><small>TransPA-tid × löneschablon</small></Link><Link prefetch={false} href={analysisHref(periodQuery,{source:"Avskrivningsregister",kind:"cost"})}><span>Avskrivningsregister</span><strong>{currency.format(numeric(dashboard.components.depreciation_cost))}</strong><small>Registrerade månadsavskrivningar</small></Link><Link prefetch={false} href={analysisHref(periodQuery,{kind:"cost"})}><span>Total kostnad</span><strong>{currency.format(numeric(metrics.total_cost))}</strong><small>Beräknat av Humla Hub</small></Link></div><p>{dashboard.coverage && (dashboard.coverage.revenue_months.length===0 || dashboard.coverage.cost_months.length===0) && "Workify-intäkter eller NEXT-kostnader saknas i urvalet. Resultatet visar därför ett ofullständigt ekonomiskt underlag. "}Resultatet innehåller bokförda kostnader, Piusi-bränsle och beräknad personalkostnad. Inköp till egen tank på konto 5360 visas som avstämning när Piusi-tankningar används, så att bränslet inte räknas dubbelt. Löneschablonen är inte en verifierad löneexport.</p></section>;
  const materialBasis = dashboard.material_separation?.active ? <section className="panel finance-basis"><h2>Material och transport</h2><p>Materialköp som tidigare belastade bilarna samlas på Grusmaterial. För material inklusive transport läggs inköpspriset på materialet och resterande intäkt på transporten. Tipp följer Trading eller sin lagerplats. Totalbeloppen ändras inte av uppdelningen.</p>{dashboard.material_separation.review_rows > 0 && <p><strong>{number.format(dashboard.material_separation.review_rows)} rader väntar på inköpsunderlag.</strong> Dessa behåller sin tidigare fördelning. <Link prefetch={false} href={analysisHref(periodQuery,{source:"Workify",kind:"revenue",level:"transaction"})}>Öppna intäktsunderlag</Link></p>}</section> : null;
  const internalHref=(category?:string)=>{const p=new URLSearchParams(periodQuery);p.delete('cost_center');if(costCenter&&!costCenter.includes(','))p.set('to_center',costCenter);if(category)p.set('internal_category',category);return '/kpi?view=internal&'+p.toString()};
  const metricCards = [
    { label: "Omsättning", value: currency.format(numeric(metrics.revenue)), icon: WalletCards, tone: "yellow" },
    { label: "Kostnader", value: currency.format(numeric(metrics.total_cost)), icon: WalletCards, tone: "orange" },
    { label: "Marginal", value: metrics.margin_pct == null ? "–" : `${number.format(numeric(metrics.margin_pct))} %`, icon: Gauge, tone: "green" },
    { label: "Resultat", value: currency.format(numeric(metrics.result)), icon: BarChart3, tone: numeric(metrics.result) >= 0 ? "green" : "red" },
    { label: "Intäkt per lastbil", value: metrics.revenue_per_vehicle==null?"–":currency.format(numeric(metrics.revenue_per_vehicle)), icon: Truck, tone: "blue", detail: "Inhyrda bilar exkluderade" },
    { label: "Omsättning / arbetad timme", value: efficiency?.revenue_per_worked_hour != null ? `${currency.format(numeric(efficiency.revenue_per_worked_hour))}/h` : "–", icon: Gauge, tone: "green", detail: scopedOperationsUnavailable?"Kostnadsställesfördelad arbetstid är inte verifierad":`${currency.format(numeric(efficiency?.own_revenue))} egen omsättning · UE/LASTBIL exkluderad` },
    { label: "Beläggningsgrad fordon", value: scopedOperationsUnavailable?"–":percentDisplay(utilization), icon: Gauge, tone: "purple" },
    { label: "Inhyrd kapacitet", value: scopedOperationsUnavailable?"–":percentDisplay(hiredShare), icon: Truck, tone: "orange", detail: scopedOperationsUnavailable?"Kostnadsställesfördelad kapacitet är inte verifierad":`${currency.format(numeric(hiredCapacity?.hired_revenue))} av ${currency.format(numeric(hiredCapacity?.total_revenue))}` },
    { label: "Dieselkostnad av omsättning", value: metrics.diesel_share==null?"–":`${number.format(numeric(metrics.diesel_share))} %`, icon: Fuel, tone: "orange" },
    { label: "Närvaro chaufförer", value: percentDisplay(attendance?.attendance_percent), icon: Users, tone: "cyan", detail: attendance?.attendance_percent==null?"Inväntar frånvarodata och schematid från TransPA":`Sjuk ${percentDisplay(attendance.sick_percent)} · VAB ${percentDisplay(attendance.vab_percent)} · semester ${percentDisplay(attendance.vacation_percent)}` },
    { label: "Genomsnittlig faktureringstid", value: dashboard.invoice_lead_time?.average_days == null ? "–" : `${number.format(dashboard.invoice_lead_time.average_days)} dagar`, icon: Gauge, tone: "blue", detail: dashboard.invoice_lead_time ? `${dashboard.invoice_lead_time.invalid_order_days>0?"Preliminärt · ":""}${number.format(dashboard.invoice_lead_time.averaged_orders??dashboard.invoice_lead_time.orders)} externa ordrar · avslut → faktura · 0 dagar räknas inte` : "Inväntar fakturadatum" },
    { label: "Faktureringstid · Elleholms Maskin", value: dashboard.invoice_lead_time?.internal_average_days == null ? "–" : `${number.format(dashboard.invoice_lead_time.internal_average_days)} dagar`, icon: Gauge, tone: "purple", detail: dashboard.invoice_lead_time ? `${number.format(dashboard.invoice_lead_time.internal_averaged_orders??0)} interna ordrar · avslut → faktura · 0 dagar räknas inte` : "Inväntar fakturadatum" },
  ];

  const selectedDefinition = DATA_KINDS[dataKind];
  const requiredComplete = useMemo(() => selectedDefinition.fields.filter((field) => field.required).every((field) => mapping[field.key]), [mapping, selectedDefinition]);
  const rulePreview = useMemo(() => {
    if (!preview) return { error: null, rows: [] };
    try {
      const rules = parseVehicleRules(vehicleRules, preview.headers);
      return { error: null, rows: preview.rows.slice(0, 12).map((row) => {
        const raw = row[mapping.vehicle_registration] ?? "";
        return { raw, ...resolveVehicle(row, raw, rules) };
      }) };
    } catch (error) {
      return { error: error instanceof Error ? error.message : "Ogiltiga kopplingar", rows: [] };
    }
  }, [preview, vehicleRules, mapping]);

  function selectFiles(files: File[]) {
    if (busy || !files.length) return;
    setFile(files[0]);
    setPendingFiles(files.slice(1));
    setPreview(null);
    setMapping({});
    setVehicleRules("");
    setKindConfirmed(!automatic);
    setMessage(null);
  }

  async function analyse() {
    if (!file) return;
    if (file.size > 4 * 1024 * 1024) {
      setMessage({ type: "error", text: "Filen överstiger 4 MB. Dela upp filen före uppladdning." });
      return;
    }
    setBusy(true);
    setMessage(null);
    const body = new FormData();
    body.set("file", file);
    body.set("dataKind", automatic ? "auto" : dataKind);
    try {
      const response = await fetch("/api/kpi/parse", { method: "POST", body, signal: AbortSignal.timeout(60_000) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Filen kunde inte analyseras.");
      setPreview(result);
      setMapping(result.suggestedMapping);
      if (result.detectedKind) {
        setDataKind(result.detectedKind);
        setKindConfirmed(true);
      } else {
        setKindConfirmed(false);
        setMessage({ type: "error", text: "Humla kunde inte avgöra datatypen säkert. Välj rätt datatyp för filen; oklara rader stoppar inte övriga rader." });
      }
    } catch (error) {
      setMessage({ type: "error", text: error instanceof Error ? error.message : "Filen kunde inte analyseras." });
    } finally {
      setBusy(false);
    }
  }

  async function importFile() {
    if (!file || !preview || !requiredComplete || !kindConfirmed || rulePreview.error) return;
    setBusy(true);
    setMessage(null);
    const body = new FormData();
    body.set("file", file);
    body.set("dataKind", dataKind);
    body.set("mapping", JSON.stringify({ ...mapping, __vehicle_rules: vehicleRules }));
    try {
      const response = await fetch("/api/kpi/import", { method: "POST", body, signal: AbortSignal.timeout(120_000) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Importen misslyckades.");
      const importCounts = typeof result.duplicateRowsSkipped === 'number'
        ? `${result.insertedRows} nya rader sparades · ${result.duplicateRowsSkipped} redan importerade rader hoppades över · ${result.ignoredZeroRows} nollrader ignorerades. ${result.invalidRows} nya rader behöver granskas.`
        : `${result.validRows} giltiga och ${result.invalidRows} rader för granskning sparades.`;
      setMessage({ type: "success", text: `${file.name}: ${importCounts} ${pendingFiles.length ? "Nästa fil ligger redo för analys." : "Klart. Öppna Översikt för uppdaterade nyckeltal."}` });
      setFile(pendingFiles[0] ?? null);
      setPendingFiles((current) => current.slice(1));
      setPreview(null);
      setMapping({});
      setVehicleRules("");
      setKindConfirmed(false);
    } catch (error) {
      setMessage({ type: "error", text: error instanceof Error && error.name === "TimeoutError" ? "Svaret dröjde. Kontrollera Senaste importer innan du försöker igen; servern kan fortfarande ha sparat filen." : error instanceof Error ? error.message : "Importen misslyckades." });
    } finally {
      setBusy(false);
    }
  }

  function chooseKind(next: DataKind) {
    setDataKind(next);
    setAutomatic(false);
    setKindConfirmed(true);
    setMapping(preview ? suggestMapping(preview.headers, next) : {});
    setMessage(null);
  }

  return <div className={`kpi-app ${view==='kpi'?workspaceStyles.kpiPage:''}`}><KpiWorkspace>
    <aside id="kpi-sidebar" className={`sidebar ${mobileMenu ? "open" : ""}`}>
      <div className="brand-wrap"><div className="brand-mark">H</div><div><div className="brand">Humla</div><div className="brand-sub">DASHBOARD</div></div><button className="icon-button close-nav" onClick={() => setMobileMenu(false)} aria-label="Stäng meny"><X size={18}/></button></div>
      <div className="workspace"><span>Arbetsyta</span><strong>{tenantName}</strong></div>
      <nav className="nav">
        <Link prefetch={false} className={view === "overview" ? "active" : ""} href={kpiHref("overview")} onClick={switchFinancialView}><LayoutDashboard size={18}/>Översikt</Link>
        <Link prefetch={false} className={view === "kpi" ? "active" : ""} href={kpiHref("kpi")} onClick={switchFinancialView}><BarChart3 size={18}/>Enhetsuppföljning</Link>
        <Link prefetch={false} href={`/kpi/transportledare?${periodQuery}`} onClick={() => setMobileMenu(false)}><Truck size={18}/>Transportledar-KPI</Link>
        <Link prefetch={false} href="/kpi/fordon" onClick={() => setMobileMenu(false)}><Gauge size={18}/>Fordon &amp; TCO</Link>
        <Link prefetch={false} href="/kpi/projekt" onClick={() => setMobileMenu(false)}><BarChart3 size={18}/>Projektuppföljning</Link>
        <Link prefetch={false} className={view === "internal" ? "active" : ""} href={kpiHref("internal")} onClick={() => setMobileMenu(false)}><Truck size={18}/>Interna körningar</Link>
        <Link prefetch={false} className={view === "monthly" ? "active" : ""} href={"/kpi/manadsrapport?"+new URLSearchParams(periodQuery)} onClick={() => setMobileMenu(false)}><FileSpreadsheet size={18}/>Månadsrapport</Link>
        {canManage&&<Link prefetch={false} href="/kpi/betalningsprognos" onClick={() => setMobileMenu(false)}><FileSpreadsheet size={18}/>Betalningsprognos</Link>}
        <Link prefetch={false} className={view === "import" ? "active" : ""} href={kpiHref("import")} onClick={() => setMobileMenu(false)}><UploadCloud size={18}/>Dataimport</Link>
        <Link className={view === "review" ? "active" : ""} href={kpiHref("review")} prefetch={false} onClick={() => setMobileMenu(false)}><CheckCircle2 size={17}/>Granskning</Link>
        <Link href={`/kpi/avstamning?${periodQuery}`} prefetch={false} onClick={() => setMobileMenu(false)}><ShieldCheck size={17}/>Avstämning &amp; regler</Link>
        {canManage&&<div className="nav-group"><span className="nav-group-title"><Settings2 size={15}/>Inställningar</span>
          <Link href={`/kpi/kontrollpanel?${periodQuery}`} prefetch={false} onClick={() => setMobileMenu(false)}><ListTree size={17}/>Kontrollpanel</Link>
          <Link className={view === "transpa" ? "active" : ""} href={kpiHref("transpa")} prefetch={false} onClick={() => setMobileMenu(false)}><Database size={17}/>TransPA-underlag</Link>
          <Link className={view === "definitions" ? "active" : ""} href={kpiHref("definitions")} prefetch={false} onClick={() => setMobileMenu(false)}><Settings2 size={17}/>KPI-guide</Link>
        </div>}
      </nav>
      <div className="sidebar-status"><div className="status-icon"><Database size={17}/></div><div><strong>Datamotor</strong><span>Ansluten</span></div><span className="live-dot"/></div>
      <div className="user-block"><div className="avatar">{userName.split(" ").map((part) => part[0]).join("").slice(0,2)}</div><div><strong>{userName}</strong><span>KPI-användare</span></div><form action={logout}><button className="logout-button" type="submit">Logga ut</button></form></div>
    </aside>

    <main className="app-main">
      <header className="topbar"><KpiSidebarToggle/><button className="icon-button mobile-nav" onClick={() => setMobileMenu(true)} aria-label="Öppna meny"><Menu size={20}/></button><div><span className="breadcrumb">Humla Dashboard / Transport</span><h1>{view === "monthly" ? "Månadsrapport – Transport" : view === "internal" ? "Interna körningar" : view === "overview" ? "Översikt" : view === "kpi" ? "Enhetsuppföljning" : view === "import" ? "Dataimport" : view === "review" ? "Granskning & mappning" : view === "accounts" ? "Kontomappning" : view === "units" ? "Enhetsmappning" : view === "transpa" ? "TransPA-underlag" : "KPI-definitioner"}</h1></div>{canManage&&<Link prefetch={false} className="secondary" href={`/kpi/kontrollpanel?${periodQuery}`}><ListTree size={16}/>Kopplingar & inställningar</Link>}{view!=='monthly'&&<div className="topbar-badge"><ShieldCheck size={16}/>Säker KPI-arbetsyta</div>}</header>
      {view==='monthly'&&<div className="content"><KpiMonthlyReport query={periodQuery}/></div>}
      {view==='internal'&&<div className="content"><form className="period-form"><input type="hidden" name="view" value="internal"/><label>Från<input type="date" name="from" defaultValue={from}/></label><label>Till<input type="date" name="to" defaultValue={to}/></label><button>Visa period</button></form><p>Urval: {from} – {to}{monthPeriod?` · månader ${monthPeriod.months.join(', ')}`:''}. Fliken visar Entreprenad → Transport och Entreprenad → Sortergården; övriga Dashboard-filter påverkar inte dessa summor.</p><InternalTransfers query={periodQuery} canManage={canManage}/></div>}
      {(view === "overview" || view === "kpi") && <div className="content">{monthPeriod ? <KpiMonthPeriod onReportChange={onPeriodChange} period={monthPeriod} costCenter={costCenter} costCenters={dashboard.cost_centers??[]} groups={dashboard.group_options??[]} unitName={dashboard.economic_units?.find(u=>u.key===activeFilters?.unit)?.label}/> : <form className="period-form"><input type="hidden" name="from" value={from}/><input type="hidden" name="to" value={to}/><input type="hidden" name="view" value={view}/><KpiCostCenterFilter value={costCenter} options={dashboard.cost_centers??[]}/><input type="hidden" name="cost_center" value={costCenter}/><button>Visa</button></form>}{costCenter&&<p>Projektregistrets kopplingar gäller från {dashboard.classification_valid_from??"registrerad giltighetsdag"}. Hela belopp följer daterade kopplingar. Osäkra kostnadsställen ligger under Ej klassificerat. Importer, granskning och administration gäller hela arbetsytan.</p>}{numeric(dashboard.unclassified_summary?.rows)>0&&<p><Link prefetch={false} href={`/kpi/analys?${periodQuery.replace(/&cost_center=[^&]*/,"")}&cost_center=unclassified`}>Ej klassificerat kostnadsställe: {currency.format(numeric(dashboard.unclassified_summary?.revenue))} intäkter · {currency.format(numeric(dashboard.unclassified_summary?.cost))} kostnader</Link>. Dessa belopp ingår i Alla kostnadsställen och inväntar säker fördelning.</p>}{scopedOperationsUnavailable&&<p>Beläggning, kapacitet och timnyckeltal per kostnadsställe inväntar verifierad fördelning. Finansiella belopp är beräknade i Hubben.</p>}</div>}
      {(view==='overview'||view==='kpi')&&!!dashboard.excluded_projects?.length&&<div className="content"><section className="panel" aria-label="Projekt utanför uppföljningen"><h2>Utanför uppföljningen</h2><p>Följande projekt ingår inte i omsättning, kostnader eller resultat i Översikt och Enhetsuppföljning:</p><ul>{dashboard.excluded_projects.map(p=><li key={p.project_id}><Link prefetch={false} href={'/kpi/projekt?'+new URLSearchParams({from,to,project:p.project_id})}>{p.name} →</Link></li>)}</ul><p>Originalunderlaget finns kvar i projektvyn för granskning.</p></section></div>}
      {(view==='overview'||view==='kpi')&&costCenter==='40'&&<div className="content"><WorkshopTimeKpi query={periodQuery}/></div>}
      {costCenter&&view!=="overview"&&view!=="kpi"&&view!=="monthly"&&<div className="content"><p>Den här vyn visar hela arbetsytan. Kostnadsställesfiltret används när du återgår till KPI eller Översikt.</p></div>}
      {serverIssues.length > 0 && <div className="content server-issues"><AlertTriangle size={18}/><div><strong>En del data kunde inte hämtas</strong><span>{serverIssues.join(" · ")}</span></div></div>}
      {(view==='overview'||view==='kpi')&&numeric(dashboard.unit_assignment_summary?.rows)>0&&<div className="content"><section className="panel" style={{borderLeft:'4px solid #e1ad27'}} aria-label="Ekonomisk enhetskoppling saknas"><h2>Enhetskopplingar behöver kompletteras</h2><p>{numeric(dashboard.unit_assignment_summary?.rows)} rader i detta urval saknar ekonomisk enhet: <strong>{currency.format(numeric(dashboard.unit_assignment_summary?.revenue))} intäkter</strong> och <strong>{currency.format(numeric(dashboard.unit_assignment_summary?.cost))} kostnader</strong>.</p><p>Beloppen ingår i totalen och kan visas på fordonet. Fördelning av ekipage och jämförelse mellan ekonomiska enheter är ofullständig tills kopplingarna kompletterats.</p>{canManage&&<Link prefetch={false} className="secondary" href={`/kpi/kontrollpanel?section=matching&${periodQuery}`}>Öppna arbetskön för mappning</Link>}</section></div>}
      {(view==='overview'||view==='kpi')&&<div className="content dashboard-report-actions no-print"><KpiPrint/><a className="secondary" href={`/api/kpi/export?${periodQuery}&level=${view==='kpi'?'unit':'group'}&grain=month&format=xlsx`}>Exportera Excel</a><a className="secondary" href={`/api/kpi/export?${periodQuery}&level=${view==='kpi'?'unit':'group'}&grain=month&format=pdf`}>Exportera PDF</a><span>Export och utskrift gäller aktuellt periodurval och aktiva filter.</span></div>}

      {(view === "overview" || view === "kpi") && pendingBatches.length>0 && <div className="content"><section className="panel"><h2>Underlag som ännu inte är klart</h2><p>Rapporten visar de rader som finns i Hubben. Följande importer är inte färdigställda:</p><ul>{pendingBatches.map(b=><li key={b.id}><Link prefetch={false} href={kpiHref("import")}>{b.file_name ?? "API-leverans"}</Link> · {statusLabel(b.status)} · {number.format(b.valid_row_count)} av {number.format(b.row_count)} giltiga rader</li>)}</ul></section></div>}
      {view === "review" && <div className="content"><WorkifyNameRules canManage={canManage}/><KpiReviewQueue key={`${from}-${to}`} from={from} to={to} canManage={canManage}/><HubReview initial={hubReviews as never[]}/></div>}
      {(view==='overview'||view==='kpi')&&<div className="content"><KpiMaterialProject unit={dashboard.economic_units?.find(u=>u.key===dashboard.material_unit_id)} unitId={dashboard.material_unit_id} query={periodQuery}/></div>}
      {(view==='overview'||view==='kpi')&&<div className="content"><KpiYearComparison key={periodQuery} query={periodQuery}/></div>}
      {(view === "overview" || view === "kpi") && <div className="content"><section className="panel"><h2>12-04 – Kranbil med Såg</h2><p>1 250 kr per debiterad sågtimme till lastbilen. Resterande intäkt och fördelade kostnader följs upp under Sågning.</p><Link prefetch={false} href={"/kpi/transportledare?activity=saw&"+periodQuery}>Öppna uppföljningen →</Link></section></div>}
      {view === "overview" && <div className="content">
        <section className="overview-hero"><div><span className="section-kicker">Verksamhetsår {overviewPeriod.label}</span><h2>Valda månader · {overviewPeriod.label}</h2><p>Jämförelsen använder motsvarande månader föregående verksamhetsår.</p></div><span className="asof">Vald rapportperiod</span></section>
        <KpiBillingBalance key={periodQuery} query={periodQuery}/>
        <section className="overview-pulse"><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Omsättning vald period</span><strong>{currency.format(currentRevenue)}</strong><small>{revenueChange == null ? "Jämförelse saknas" : `${revenueChange >= 0 ? "+" : ""}${number.format(revenueChange)} % mot fg. år`}</small></Link><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Resultatmarginal</span><strong>{resultMargin == null ? "–" : `${number.format(resultMargin)} %`}</strong><small>{previousMargin == null ? "Fg. år saknas" : `Fg. år ${number.format(previousMargin)} %`}</small></Link><Link prefetch={false} href={kpiHref("review")}><span>Granska underlag</span><strong>Öppna</strong><small>Avvikelser och fördelning</small></Link><Link prefetch={false} href={kpiHref("review")}><span>Rader i beräkningen</span><strong>{number.format(validRows)}</strong><small>Importerade och beräknade rader</small></Link></section>
        <section className="metrics-grid">{metricCards.map(({label,value,icon:Icon,tone,detail})=><Link prefetch={false} className="metric-card overview-card" href={label==="Närvaro chaufförer"?`/kpi?${periodQuery}#narvaro`:label==="Genomsnittlig faktureringstid"?`/kpi/fakturering?${periodQuery}&invoice_customer=external`:label==="Faktureringstid · Elleholms Maskin"?`/kpi/fakturering?${periodQuery}&invoice_customer=internal`:analysisHref(periodQuery,label==="Kostnader"?{kind:"cost"}:label==="Omsättning"?{kind:"revenue"}:{})} key={label}><div className={`metric-icon ${tone}`}><Icon size={20}/></div><span>{label}</span><strong>{value}</strong><small>{detail??"Beräknat i Humla Hub"}</small></Link>)}</section><section className="panel"><div className="panel-head"><div><span className="section-kicker">Interna projekt · Elleholms Maskin AB</span><h2>Fakturerade interna intäkter</h2></div></div><section className="metrics-grid">{[{label:'Internt · totalt',value:internal?.total,share:internal?.total_percent,category:undefined},{label:'Internt · grusmaterial',value:internal?.material,share:internal?.material_percent,category:'material'},{label:'Internt · deponi / tippavgifter',value:internal?.tipp_deponi,share:internal?.tipp_deponi_percent,category:'tipp_deponi'}].map(({label,value,share,category})=><Link prefetch={false} className="metric-card overview-card" href={internalHref(category)} key={label}><div className="metric-icon yellow"><Truck size={20}/></div><span>{label}</span><strong>{value==null?'–':currency.format(value)}</strong><small>{percentDisplay(share)} av KPI-omsättningen i valt urval</small><InternalYearChange comparison={internalComparison} metric={category??'total'}/></Link>)}<div className="metric-card overview-card"><div className="metric-icon yellow"><Truck size={20}/></div><span>Internt · mellanskillnad material</span><strong>{internal?.material_margin?.difference==null?'–':currency.format(internal.material_margin.difference)}</strong><small>{percentDisplay(internal?.material_margin?.margin_percent)} av fakturerat internpris</small><InternalYearChange comparison={internalComparison} metric="material_margin.difference"/><small>Preliminärt · prisunderlag</small><small>Fakturerat internpris: {internal?.material_margin?.billed==null?'–':currency.format(internal.material_margin.billed)}</small><small>Beräknat inköp: {internal?.material_margin?.purchase_cost==null?'–':currency.format(internal.material_margin.purchase_cost)}</small></div></section><p>{internal?.material_margin?.basis??'Inväntar jämförelse av internpris och inköp.'}</p>{internal?.material_margin&&<><p>{internal.material_margin.rows} av {internal.material_margin.rows} materialrader ingår. {internal.material_margin.estimated_rows} rader har uppskattat eller preliminärt prisunderlag, varav {internal.material_margin.fallback_rows} rader om {currency.format(internal.material_margin.fallback_billed)} har kompletterats med överslag.</p>{!!internal.material_margin.missing_rows&&<p>Inköpskostnaden kan ännu inte beräknas för {internal.material_margin.missing_rows} rader om {currency.format(internal.material_margin.missing_billed)}. Alla internintäkter är med; total mellanskillnad visas när kostnadsunderlaget är komplett.</p>}{!!internal.material_margin.bundled_rows&&<p>{internal.material_margin.bundled_rows} rader faktureras inklusive transport ({currency.format(internal.material_margin.bundled_billed)}). Deras mellanskillnad innehåller även transport och är inte ren materialmarginal.</p>}<details><summary>Visa internpris, inköp och prisunderlag per rad</summary><div className="monthly-scroll" role="region" aria-label="Internmaterial – internpris och inköpsunderlag" tabIndex={0}><table><thead><tr><th>Datum / order</th><th>Artikel</th><th>Internpris</th><th>Beräknat inköp</th><th>Mellanskillnad</th><th>Prisunderlag</th></tr></thead><tbody>{internal.material_margin.details?.map(row=><tr key={row.source_row}><td><Link prefetch={false} href={analysisHref(periodQuery,{kind:'revenue',category:'material',date_from:row.date,date_to:row.date,level:'transaction'})}>{row.date} · {row.order_number??'–'}</Link></td><td>{row.article??'Material'}{row.bundled?' · inkl. transport':''}</td><td>{currency.format(row.billed)}</td><td>{row.purchase_cost==null?'Underlag saknas':currency.format(row.purchase_cost)}</td><td>{row.difference==null?'–':currency.format(row.difference)}</td><td>{row.fallback?'Överslag · ':row.evidence?.status==='receipt_price_list'?'Prislista / kvitto · ':'Preliminärt · '}{row.evidence?.price_source??'Underlag saknas'}<details><summary>Prisdetaljer</summary><p>{row.evidence?.rate??'–'} kr/{row.evidence?.unit??'enhet'} · {row.evidence?.quantity??'–'} {row.evidence?.unit??''}</p><p>{row.evidence?.note??'Inga ytterligare prisuppgifter.'}</p></details></td></tr>)}</tbody></table></div></details></>}<p>{internal?.basis??'Inväntar internt underlag från Hubben.'}</p>{!!internal?.pending_rows&&<p><strong>Ännu inte fakturerat:</strong> {currency.format(internal.pending_amount??0)} på {internal.pending_rows} interna rader i publicerat underlag. Visas separat och ingår inte i kortens fakturerade belopp.</p>}{!!internal?.review_rows&&<p>{internal.review_rows} fakturerade interna rader om {currency.format(internal.review_amount)} ingår i totalen men behöver kompletterad klassificering. <Link prefetch={false} href={internalHref()}>Öppna bokföringskontrollen</Link></p>}<p><Link prefetch={false} href={internalHref()}>Interna överföringar och bokföringskontroll →</Link></p></section>
        <KpiOverh…9165 tokens truncated…=='assigned';
 return <KpiDetailShell query={base} title="Transportledar-KPI" extraNavigation={<Link href={'/kpi/transportledare?'+base}>Transportledar-KPI</Link>}><div className="content">
 <section className="panel"><div className="panel-head"><div><h2>{saw?'Kranbil med Såg – egen uppföljning':unit?selected?.unit_name??'Enhetsunderlag':selfView?'Mina kostnadsenheter':'Transport – samlad uppföljning'}</h2><p>{from} – {to}{selfView?' · Enbart tilldelade enheter, på de datum ansvaret gäller':' · KST 30'}</p></div><KpiPrint/></div>
 <nav style={{display:'flex',gap:16,marginBottom:16}}><Link href={'/kpi/transportledare?'+base}>Balans per enhet</Link><Link href={'/kpi/transportledare?'+sawParams}>12-04 · Kranbil med Såg</Link></nav>
 <form method="get" className="form-grid">{unit&&<input type="hidden" name="unit" value={unit}/>}{saw&&<input type="hidden" name="activity" value="saw"/>}{group&&<input type="hidden" name="group" value={group}/>}{months&&<input type="hidden" name="months" value={months.join(',')}/>}<label>Från<input type="date" name="from" defaultValue={from} required/></label><label>Till<input type="date" name="to" defaultValue={to} required/></label>{owner&&<label>Ansvar<select name="user_id" defaultValue={targetUser??''}><option value="">Alla enheter inom Transport</option>{people?.map(p=><option key={p.user_id} value={p.user_id}>{p.display_name??'Användare'} – tilldelade enheter</option>)}</select></label>}<button type="submit">Visa</button></form>
 <p>{months&&<>Valda månader: {months.join(', ')}. <Link href={'/kpi/transportledare?'+new URLSearchParams({from,to,...periodScope})}>Visa alla månader i datumintervallet</Link> · </>}<Link href={'/kpi/transportledare?'+new URLSearchParams({from:`${fy}-09-01`,to:todayText,...periodScope})}>YTD till dagens datum</Link>{owner&&<> · <Link href="/transport-styrning/admin">Hantera tilldelningar</Link></>}</p></section>
 {error||!report?<section className="panel" role="alert"><h2>Styrkortet kunde inte hämtas</h2><p>Kontrollera behörighet och publicerat rapportunderlag. Saknade belopp visas inte som noll.</p></section>:saw?<SawFollowup report={sawData as SawReport|null}/>:<>
 <section className="metrics-grid">{([['Omsättning','revenue'],['Kostnader','cost'],['Resultat','result']]as const).map(([label,key])=><article className="metric-card" key={key}><span>{label}</span><strong>{money(report.summary[key])}</strong><small>Samma period fg. år: {money(prior?.summary[key])}</small></article>)}<article className="metric-card"><span>Marginal i urvalet</span><KpiMarginGauge label="Urvalet" margin={report.summary.margin_percent} target={report.summary.target_margin_percent}/><small>Samma period fg. år: {pct(prior?.summary.margin_percent)}</small></article></section>
 {!report.units.length&&<section className="panel"><h2>Inget underlag i urvalet</h2><p>{selfView?'Inga transaktioner är kopplade till dina tilldelade enheter under dessa datum. En ägare kan lägga in ansvar med giltighetsdatum.':'Det finns inga publicerade transaktioner för urvalet.'}</p></section>}
 <TransportBalanceCards report={report} prior={prior} base={base} selectedUnit={unit} selectedGroup={group}/><TransportBreakdowns report={report} prior={prior}/>
 <section className="panel"><details><summary>Ekonomiska enheter – tabell och målavvikelser</summary><div className="monthly-scroll"><table><thead><tr><th>Enhet</th><th>Omsättning</th><th>Kostnad</th><th>Resultat</th><th>Marginal</th><th>Mål</th><th>Avvikelse</th><th>Avvikelse kr</th></tr></thead><tbody>{report.units.map(u=><tr key={u.unit_id??'unassigned'}><td>{u.unit_id?<Link prefetch={false} href={'/kpi/transportledare?'+base+'&unit='+u.unit_id}>{u.unit_name??'Enhet'}</Link>:'Ej kopplat till enhet'}</td><td>{money(u.revenue)}</td><td>{money(u.cost)}</td><td>{money(u.result)}</td><td>{pct(u.margin_percent)}</td><td>{pct(u.target_margin_percent)}</td><td>{pct(u.deviation_pp,'pp')}</td><td>{u.deviation_amount==null?'Ej angivet':money(u.deviation_amount)}</td></tr>)}</tbody></table></div><p>Mål beräknas per transaktionsdatum och vägs med omsättningen. Saknas mål för en del av omsättningen visas inget sammanvägt mål. Inga exempelvärden har lagts in.</p>{report.summary.unassigned_rows>0&&<p>{report.summary.unassigned_rows} rader saknar ekonomisk enhet och ingår i totalsumman under ”Ej kopplat till enhet”.</p>}</details></section>
 <section className="panel"><h2>Transport, material och tippavgifter</h2><div className="monthly-scroll"><table><thead><tr><th>Del</th><th>Intäkt</th><th>Direkta kostnader</th><th>Resultat</th><th>Marginal</th></tr></thead><tbody>{report.sections.map(s=><tr key={s.section}><td>{labels[s.section]??s.section}</td><td>{money(s.revenue)}</td><td>{money(s.cost)}</td><td>{s.result==null?'Ej fullständigt fördelat':money(s.result)}</td><td>{s.margin_percent==null?'–':pct(s.margin_percent)}</td></tr>)}</tbody></table></div><p>Personal, bränsle, fasta kostnader och andra kostnader utan verifierad artikelkoppling ligger under Övrigt / gemensamt. De ingår i enhetens totala resultat. Delarnas resultat och marginal visas först när kostnaderna är fullständigt fördelade; kombinerade artiklar delas enligt Hub-reglerna.</p></section>
 {unit&&<section className="panel"><h2>Arbetsorder och originalrader</h2><p>100 transaktioner per sida. Alla tilldelade körningar ingår, även körningar inom andra områden. Kostnader utan verifierad orderkoppling ligger kvar som enhetskostnad.</p><div className="monthly-scroll"><table><thead><tr><th>Datum / order</th><th>Kund / projekt</th><th>Källa</th><th>Kategori</th><th>Typ</th><th>Belopp / original</th></tr></thead><tbody>{report.transactions.map(t=><tr key={t.fact_id}><td>{t.occurred_on} · {t.order_number??'Ingen orderkoppling'}</td><td>{t.customer??'–'} / {t.project??'–'}</td><td>{t.source}</td><td>{labels[t.category]??t.category}</td><td>{t.kind==='revenue'?'Intäkt':'Kostnad'}</td><td><details><summary>{money(t.amount)}</summary><pre style={{whiteSpace:'pre-wrap',maxWidth:600}}>{JSON.stringify(t.original,null,2)}</pre></details></td></tr>)}</tbody></table></div><nav aria-label="Underlagssidor">{page>0&&<Link href={'/kpi/transportledare?'+base+'&unit='+unit+'&page='+(page-1)}>← Föregående</Link>} {report.transactions.length===100&&<Link href={'/kpi/transportledare?'+base+'&unit='+unit+'&page='+(page+1)}>Nästa →</Link>}</nav></section>}
 {owner&&unit&&selected&&<section className="panel"><h2>Målmarginal – {selected.unit_name}</h2>{q.saved&&<p role="status">{q.saved==='yes'?'Målet är sparat.':'Målet kunde inte sparas. Kontrollera datum, värde och om ett mål redan finns på eller efter valt startdatum.'}</p>}<form action={saveTransportTarget} className="form-grid"><input type="hidden" name="unit_id" value={unit}/><input type="hidden" name="group" value={group??''}/><input type="hidden" name="from" value={from}/><input type="hidden" name="to" value={to}/><input type="hidden" name="user_id" value={targetUser??''}/><input type="hidden" name="months" value={months?.join(',')??''}/><label>Målmarginal, %<input type="number" name="margin" min="-100" max="100" step="0.1" required/></label><label>Gäller från<input type="date" name="valid_from" defaultValue={from} required/></label><label>Motivering<input name="reason" minLength={3} maxLength={1000} required/></label><button type="submit">Spara nytt mål</button></form><p>Ett nytt mål avslutar föregående mål dagen innan. Tidigare målperioder behålls.</p></section>}
 <p>Publicerat underlag: {report.synced_at?new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'}).format(new Date(report.synced_at)):'–'}. Samma Hub-underlag som Enhetsuppföljningen.</p>
 </>}
 </div></KpiDetailShell>;
}
