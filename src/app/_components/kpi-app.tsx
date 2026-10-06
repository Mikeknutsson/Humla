"use client";
import {KpiCostCenterFilter} from './kpi-cost-center-filter';

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

import Link from "next/link";
import {useSearchParams} from "next/navigation";
import {InternalTransfers} from './internal-transfers';
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

export type Dashboard = {
  group_options?:string[];
  economic_units?:EconomicUnit[];
  comparison_available?:boolean;
  coverage?:{revenue_months:number[];cost_months:number[]};
  unclassified_summary?: Record<string,number|null>;
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
  provenance?: {cost_center?:string};
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
  initialView?: "overview" | "kpi" | "import" | "definitions" | "accounts" | "units" | "transpa" | "review" | "internal";
  serverIssues?: string[];
  onPeriodChange?: (query:string)=>Promise<void>;
};

export function KpiApp({ monthPeriod, overviewMonthly, activeFilters, dashboard, overviewPrevious, overviewPeriod, batches, units, unitReport, transpaEvidence, transpaVehicleTime, efficiency, hiredCapacity, driverProductivity, hubReviews, tenantName, userName, from, to, canManage, initialView = "overview", serverIssues = [], onPeriodChange }: KpiAppProps) {
  const liveQuery=useSearchParams();
  const financialView=initialView==='overview'||initialView==='kpi';
  const view=financialView?(liveQuery.get('view')==='kpi'?'kpi':'overview'):initialView;
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

  useEffect(() => { localStorage.setItem("humla:kpi:period", JSON.stringify({ from, to })); document.cookie = `humla_kpi_from=${from}; Path=/; Max-Age=31536000; SameSite=Lax`; document.cookie = `humla_kpi_to=${to}; Path=/; Max-Age=31536000; SameSite=Lax`; }, [from, to]);
  const scopedOperationsUnavailable = Boolean(dashboard.scoped_operational_unavailable);
  const costCenter = dashboard.cost_center_scope ?? activeFilters.cost_center ?? "";
  const scopeQuery = costCenter ? `&cost_center=${encodeURIComponent(costCenter)}` : "";
  const filterQuery = new URLSearchParams(Object.entries(activeFilters).filter(([k])=>k!=="cost_center")).toString();
  const periodQuery = (monthPeriod ? monthPeriodQuery(monthPeriod) : `from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`)+scopeQuery+(filterQuery?`&${filterQuery}`:"");
  const kpiHref = (nextView?: string) => `/kpi?${nextView ? `view=${nextView}&` : ""}${periodQuery}`;
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
  const productivePercent = driverProductivity?.productive_percent;
  const percentDisplay = (value: unknown) => value == null ? "–" : `${number.format(numeric(value))} %`;
  const productiveHours = numeric(driverProductivity?.productive_hours);
  const unclassifiedHours = numeric(driverProductivity?.unclassified_hours);
  const missingVehicle = numeric(dashboard.quality?.rows_without_vehicle);
  const missingEmployee = numeric(dashboard.quality?.rows_without_employee);
  const unmappedAccounts = numeric(dashboard.quality?.rows_without_account_mapping);
  const attentionItems = [
    reviewCount > 0 ? {label:"Behöver granskas",value:String(reviewCount),detail:"Öppna granskningsfall",href:kpiHref("review")} : null,
    unmappedAccounts > 0 ? {label:"Konton utan klassificering",value:number.format(unmappedAccounts),detail:"Påverkar kostnadsanalysen",href:kpiHref("accounts")} : null,
    missingVehicle > 0 ? {label:"Rader utan fordon",value:number.format(missingVehicle),detail:"Kan inte fördelas på fordonsnivå",href:kpiHref("kpi")} : null,
    missingEmployee > 0 ? {label:"Tid utan personkoppling",value:number.format(missingEmployee),detail:"Påverkar personaluppföljningen",href:kpiHref("kpi")} : null,
  ].filter(Boolean) as Array<{label:string;value:string;detail:string;href:string}>;
  const financeBasis = <section className="panel finance-basis"><div className="panel-head"><div><span className="section-kicker">Ekonomiskt underlag</span><h2>Så räknas intäkter och kostnader</h2></div></div><p>Intäkterna kommer från Workifys artikelrader efter artikeldatum. Alla orderstatusar med giltiga belopp ingår; summan kan därför skilja sig från bokförd eller enbart fakturerad omsättning.</p><div className="mini-kpi-grid"><Link prefetch={false} href={analysisHref(periodQuery,{source:"NEXT",kind:"cost"})}><span>Importerade NEXT-kostnader</span><strong>{currency.format(numeric(dashboard.components.next_total_cost))}</strong><small>Bokförda kostnadsrader</small></Link><Link prefetch={false} href={analysisHref(periodQuery,{source:"TransPA",kind:"cost"})}><span>Beräknad personalkostnad</span><strong>{currency.format(numeric(dashboard.components.transpa_personnel_cost))}</strong><small>TransPA-tid × löneschablon</small></Link><Link prefetch={false} href={analysisHref(periodQuery,{source:"Avskrivningsregister",kind:"cost"})}><span>Avskrivningsregister</span><strong>{currency.format(numeric(dashboard.components.depreciation_cost))}</strong><small>Registrerade månadsavskrivningar</small></Link><Link prefetch={false} href={analysisHref(periodQuery,{kind:"cost"})}><span>Total kostnad</span><strong>{currency.format(numeric(metrics.total_cost))}</strong><small>Beräknat av Humla Hub</small></Link></div><p>{dashboard.coverage && (dashboard.coverage.revenue_months.length===0 || dashboard.coverage.cost_months.length===0) && "Workify-intäkter eller NEXT-kostnader saknas i urvalet. Resultatet visar därför ett ofullständigt ekonomiskt underlag. "}Resultatet innehåller både bokförda kostnader och beräknad personalkostnad. Löneschablonen är inte en verifierad löneexport.</p></section>;
  const metricCards = [
    { label: "Omsättning", value: currency.format(numeric(metrics.revenue)), icon: WalletCards, tone: "yellow" },
    { label: "Kostnader", value: currency.format(numeric(metrics.total_cost)), icon: WalletCards, tone: "orange" },
    { label: "Marginal", value: metrics.margin_pct == null ? "–" : `${number.format(numeric(metrics.margin_pct))} %`, icon: Gauge, tone: "green" },
    { label: "Resultat", value: currency.format(numeric(metrics.result)), icon: BarChart3, tone: numeric(metrics.result) >= 0 ? "green" : "red" },
    { label: "Intäkt per lastbil", value: metrics.revenue_per_vehicle==null?"–":currency.format(numeric(metrics.revenue_per_vehicle)), icon: Truck, tone: "blue" },
    { label: "Omsättning / arbetad timme", value: efficiency?.revenue_per_worked_hour != null ? `${currency.format(numeric(efficiency.revenue_per_worked_hour))}/h` : "–", icon: Gauge, tone: "green", detail: scopedOperationsUnavailable?"Kostnadsställesfördelad arbetstid är inte verifierad":`${currency.format(numeric(efficiency?.own_revenue))} egen omsättning · UE/LASTBIL exkluderad` },
    { label: "Beläggningsgrad fordon", value: scopedOperationsUnavailable?"–":percentDisplay(utilization), icon: Gauge, tone: "purple" },
    { label: "Inhyrd kapacitet", value: scopedOperationsUnavailable?"–":percentDisplay(hiredShare), icon: Truck, tone: "orange", detail: scopedOperationsUnavailable?"Kostnadsställesfördelad kapacitet är inte verifierad":`${currency.format(numeric(hiredCapacity?.hired_revenue))} av ${currency.format(numeric(hiredCapacity?.total_revenue))}` },
    { label: "Dieselkostnad av omsättning", value: metrics.diesel_share==null?"–":`${number.format(numeric(metrics.diesel_share))} %`, icon: Fuel, tone: "orange" },
    { label: "Intäktskopplad tid chaufför", value: scopedOperationsUnavailable?"–":percentDisplay(productivePercent), icon: Users, tone: "cyan", detail: scopedOperationsUnavailable?"Kostnadsställesfördelad förartid är inte verifierad":`${number.format(numeric(driverProductivity?.productive_hours))} h av ${number.format(numeric(driverProductivity?.total_hours))} h · ${number.format(numeric(driverProductivity?.unclassified_hours))} h oklassificerat` },
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
      const response = await fetch("/api/kpi/import", { method: "POST", body, signal: AbortSignal.timeout(60_000) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Importen misslyckades.");
      setMessage({ type: "success", text: `${file.name}: ${result.validRows} giltiga och ${result.invalidRows} rader för granskning sparades. ${pendingFiles.length ? "Nästa fil ligger redo för analys." : "Klart. Öppna Översikt för uppdaterade nyckeltal."}` });
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
        <Link prefetch={false} className={view === "overview" ? "active" : ""} href={kpiHref()} onClick={switchFinancialView}><LayoutDashboard size={18}/>Översikt</Link>
        <Link prefetch={false} className={view === "kpi" ? "active" : ""} href={kpiHref("kpi")} onClick={switchFinancialView}><BarChart3 size={18}/>KPI</Link>
        <Link prefetch={false} className={view === "internal" ? "active" : ""} href={kpiHref("internal")} onClick={() => setMobileMenu(false)}><Truck size={18}/>Interna körningar</Link>
        <Link prefetch={false} className={view === "import" ? "active" : ""} href={kpiHref("import")} onClick={() => setMobileMenu(false)}><UploadCloud size={18}/>Dataimport</Link>
        <Link className={view === "review" ? "active" : ""} href={kpiHref("review")} prefetch={false} onClick={() => setMobileMenu(false)}><CheckCircle2 size={17}/>Granskning</Link>
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
      <header className="topbar"><KpiSidebarToggle/><button className="icon-button mobile-nav" onClick={() => setMobileMenu(true)} aria-label="Öppna meny"><Menu size={20}/></button><div><span className="breadcrumb">Humla Dashboard / Transport</span><h1>{view === "internal" ? "Interna körningar" : view === "overview" ? "Översikt" : view === "kpi" ? "KPI – Transport" : view === "import" ? "Dataimport" : view === "review" ? "Granskning & mappning" : view === "accounts" ? "Kontomappning" : view === "units" ? "Enhetsmappning" : view === "transpa" ? "TransPA-underlag" : "KPI-definitioner"}</h1></div>{canManage&&<Link prefetch={false} className="secondary" href={`/kpi/kontrollpanel?${periodQuery}`}><ListTree size={16}/>Kopplingar & inställningar</Link>}<div className="topbar-badge"><ShieldCheck size={16}/>Säker KPI-arbetsyta</div></header>
      {view==='internal'&&<div className="content"><form className="period-form"><input type="hidden" name="view" value="internal"/><label>Från<input type="date" name="from" defaultValue={from}/></label><label>Till<input type="date" name="to" defaultValue={to}/></label><button>Visa period</button></form><p>Urval: {from} – {to}{monthPeriod?` · månader ${monthPeriod.months.join(', ')}`:''}. Kostnadsställesfiltret i fliken omfattar båda sidor av omföringen.</p><InternalTransfers query={periodQuery} canManage={canManage}/></div>}
      {(view === "overview" || view === "kpi") && <div className="content">{monthPeriod ? <KpiMonthPeriod onReportChange={onPeriodChange} period={monthPeriod} costCenter={costCenter} costCenters={dashboard.cost_centers??[]} groups={dashboard.group_options??[]} unitName={dashboard.economic_units?.find(u=>u.key===activeFilters?.unit)?.label}/> : <form className="period-form"><input type="hidden" name="from" value={from}/><input type="hidden" name="to" value={to}/><input type="hidden" name="view" value={view}/><KpiCostCenterFilter value={costCenter} options={dashboard.cost_centers??[]}/><input type="hidden" name="cost_center" value={costCenter}/><button>Visa</button></form>}{costCenter&&<p>Projektregistrets kopplingar gäller från {dashboard.classification_valid_from??"registrerad giltighetsdag"}. Hela belopp följer daterade kopplingar. Osäkra kostnadsställen ligger under Ej klassificerat. Importer, granskning och administration gäller hela arbetsytan.</p>}{numeric(dashboard.unclassified_summary?.rows)>0&&<p><Link prefetch={false} href={`/kpi/analys?${periodQuery.replace(/&cost_center=[^&]*/,"")}&cost_center=unclassified`}>Ej klassificerat kostnadsställe: {currency.format(numeric(dashboard.unclassified_summary?.revenue))} intäkter · {currency.format(numeric(dashboard.unclassified_summary?.cost))} kostnader</Link>. Dessa belopp ingår i Alla kostnadsställen och inväntar säker fördelning.</p>}{scopedOperationsUnavailable&&<p>Beläggning, kapacitet och timnyckeltal per kostnadsställe inväntar verifierad fördelning. Finansiella belopp är beräknade i Hubben.</p>}</div>}
      {costCenter&&view!=="overview"&&view!=="kpi"&&<div className="content"><p>Den här vyn visar hela arbetsytan. Kostnadsställesfiltret används när du återgår till KPI eller Översikt.</p></div>}
      {serverIssues.length > 0 && <div className="content server-issues"><AlertTriangle size={18}/><div><strong>En del data kunde inte hämtas</strong><span>{serverIssues.join(" · ")}</span></div></div>}
      {(view==='overview'||view==='kpi')&&<div className="content dashboard-report-actions no-print"><KpiPrint/><a className="secondary" href={`/api/kpi/export?${periodQuery}&level=${view==='kpi'?'unit':'group'}&grain=month&format=xlsx`}>Exportera Excel</a><a className="secondary" href={`/api/kpi/export?${periodQuery}&level=${view==='kpi'?'unit':'group'}&grain=month&format=pdf`}>Exportera PDF</a><span>Export och utskrift gäller aktuellt periodurval och aktiva filter.</span></div>}

      {(view === "overview" || view === "kpi") && pendingBatches.length>0 && <div className="content"><section className="panel"><h2>Underlag som ännu inte är klart</h2><p>Rapporten visar de rader som finns i Hubben. Följande importer är inte färdigställda:</p><ul>{pendingBatches.map(b=><li key={b.id}><Link prefetch={false} href={kpiHref("import")}>{b.file_name ?? "API-leverans"}</Link> · {statusLabel(b.status)} · {number.format(b.valid_row_count)} av {number.format(b.row_count)} giltiga rader</li>)}</ul></section></div>}
      {view === "review" && <div className="content"><HubReview initial={hubReviews as never[]}/></div>}
      {view === "overview" && <div className="content">
        <section className="overview-hero"><div><span className="section-kicker">Verksamhetsår {overviewPeriod.label}</span><h2>Valda månader · {overviewPeriod.label}</h2><p>Jämförelsen använder motsvarande månader föregående verksamhetsår.</p></div><span className="asof">Vald rapportperiod</span></section>
        <section className="overview-pulse"><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Omsättning vald period</span><strong>{currency.format(currentRevenue)}</strong><small>{revenueChange == null ? "Jämförelse saknas" : `${revenueChange >= 0 ? "+" : ""}${number.format(revenueChange)} % mot fg. år`}</small></Link><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Resultatmarginal</span><strong>{resultMargin == null ? "–" : `${number.format(resultMargin)} %`}</strong><small>{previousMargin == null ? "Fg. år saknas" : `Fg. år ${number.format(previousMargin)} %`}</small></Link><Link prefetch={false} href={kpiHref("review")}><span>Granska underlag</span><strong>Öppna</strong><small>Avvikelser och fördelning</small></Link><Link prefetch={false} href={kpiHref("review")}><span>Rader i beräkningen</span><strong>{number.format(validRows)}</strong><small>Importerade och beräknade rader</small></Link></section>
        <section className="metrics-grid">{metricCards.map(({label,value,icon:Icon,tone,detail})=><Link prefetch={false} className="metric-card overview-card" href={analysisHref(periodQuery,label==="Kostnader"?{kind:"cost"}:label==="Omsättning"?{kind:"revenue"}:{})} key={label}><div className={`metric-icon ${tone}`}><Icon size={20}/></div><span>{label}</span><strong>{value}</strong><small>{detail??"Beräknat i Humla Hub"}</small></Link>)}</section>
        <KpiMonthChart points={overviewMonthly} query={periodQuery}/>
        {costBreakdown}
        {financeBasis}
        {!scopedOperationsUnavailable&&<section className="overview-operations"><div className="panel"><div className="panel-head"><div><span className="section-kicker">Drift & fordon</span><h2>Kapacitet och nyttjande</h2></div></div><div className="mini-kpi-grid"><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Beläggningsgrad</span><strong>{percentDisplay(utilization)}</strong><small>{number.format(reportedHours)} av {number.format(availableHours)} h</small></Link><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Fordon i underlaget</span><strong>{number.format(vehicleCount)}</strong><small>Fordon med TransPA-tid</small></Link><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Inhyrd kapacitet</span><strong>{percentDisplay(hiredShare)}</strong><small>{currency.format(numeric(hiredCapacity?.hired_revenue))} omsättning</small></Link><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Intäkt / lastbil</span><strong>{metrics.revenue_per_vehicle == null ? "–" : currency.format(numeric(metrics.revenue_per_vehicle))}</strong><small>För vald period</small></Link></div></div><div className="panel"><div className="panel-head"><div><span className="section-kicker">Personal & kapacitet</span><h2>Arbetad och intäktskopplad tid</h2></div></div><div className="mini-kpi-grid"><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Arbetad tid</span><strong>{number.format(reportedHours)} h</strong><small>Rapporterad fordonstid</small></Link><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Intäktskopplad tid</span><strong>{percentDisplay(productivePercent)}</strong><small>{number.format(productiveHours)} h</small></Link><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Oklassificerad tid</span><strong>{number.format(unclassifiedHours)} h</strong><small>Saknar intäktskoppling</small></Link><Link prefetch={false} href={kpiHref("kpi")} onClick={switchFinancialView}><span>Omsättning / timme</span><strong>{efficiency?.revenue_per_worked_hour!=null ? currency.format(numeric(efficiency.revenue_per_worked_hour))+"/h" : "–"}</strong><small>Egen omsättning / TransPA-tid</small></Link></div></div></section>}
        <section className="panel attention-panel"><div className="panel-head"><div><span className="section-kicker">Uppmärksamhet</span><h2>Datapunkter som kräver åtgärd</h2></div><strong>{attentionItems.length || "Inga"}</strong></div>{attentionItems.length ? <div className="attention-grid">{attentionItems.map((item)=><Link prefetch={false} href={item.href} key={item.label}><span>{item.label}</span><strong>{item.value}</strong><small>{item.detail}</small></Link>)}</div> : <p className="attention-empty">Inga identifierade datakvalitetsavvikelser i vald period.</p>}</section>
        <section className="panel cost-efficiency-panel"><div className="panel-head"><div><span className="section-kicker">Kostnad & effektivitet</span><h2>Kostnad per arbetad timme</h2></div><small>{workedHours>0?`${number.format(workedHours)} arbetade timmar i underlaget`:"Inväntar TransPA-tid"}</small></div><div className="cost-kpi-grid">{costCards.map((item)=><Link prefetch={false} href={analysisHref(periodQuery,{kind:"cost",category:item.category??null})} className="cost-kpi" key={item.label}><span>{item.label}</span><strong>{item.value}</strong><small>{item.detail}</small></Link>)}</div></section>
        <section className="overview-grid"><article className="panel"><div className="panel-head"><div><span className="section-kicker">Jämförelse</span><h2>Vald period mot föregående år</h2></div></div><div className="ytd-bars"><div><span>Omsättning</span><strong>{currency.format(currentRevenue)}</strong><small>{dashboard.comparison_available === false ? "Fg. år: jämförbart underlag saknas" : `Fg. år ${currency.format(previousRevenue)}`}{revenueChange != null ? ` · ${revenueChange >= 0 ? "+" : ""}${number.format(revenueChange)} %` : ""}</small></div><div><span>Resultat</span><strong>{currency.format(currentResult)}</strong><small>{dashboard.comparison_available === false ? "Fg. år: jämförbart underlag saknas" : `Fg. år ${currency.format(previousResult)}`}</small></div><div><span>Resultatmarginal</span><strong>{resultMargin == null ? "–" : `${number.format(resultMargin)} %`}</strong><small>{previousMargin == null ? "Fg. år saknas" : `Fg. år ${number.format(previousMargin)} %`}</small></div></div></article><article className="panel"><div className="panel-head"><div><span className="section-kicker">Snabbläge</span><h2>Datakvalitet</h2></div></div><p>{numeric(dashboard.quality.valid_rows)} giltiga rader · {numeric(dashboard.quality.rows_without_vehicle)} utan fordonskoppling · {numeric(dashboard.quality.rows_without_employee)} utan chaufförskoppling.</p><Link prefetch={false} className="quality-link" href={kpiHref("review")}>Öppna granskning <ChevronRight size={14}/></Link></article></section>
      </div>}
      {view === "kpi" && <div className="content">
        {!monthPeriod&&<section className="period-bar"><div><span className="section-kicker">Rapportperiod</span><strong>{from} – {to}</strong><div className="period-shortcuts">{fiscalYears.map((year) => <Link prefetch={false} key={year.label} className={from === year.from && to === year.to ? "active" : ""} href={`/kpi?${view === "kpi" ? "view=kpi&" : ""}from=${year.from}&to=${year.to}${scopeQuery}`}>{year.label}</Link>)}</div></div><form className="period-form"><input type="hidden" name="cost_center" value={costCenter}/>{view === "kpi" && <input type="hidden" name="view" value="kpi"/>}<label>Från<input type="date" name="from" defaultValue={from}/></label><label>Till<input type="date" name="to" defaultValue={to}/></label><button type="submit"><RefreshCw size={15}/>Uppdatera</button></form></section>}

        <section className="metrics-grid">{metricCards.map(({ label, value, icon: Icon, tone, detail }) => <Link prefetch={false} className="metric-card" href={analysisHref(periodQuery,label==="Kostnader"?{kind:"cost"}:label==="Omsättning"?{kind:"revenue"}:{})} key={label}><div className={`metric-icon ${tone}`}><Icon size={20}/></div><span>{label}</span><strong>{value}</strong><small>{detail ? detail : label === "Beläggningsgrad fordon" && transpaVehicleTime?.reported_hours ? `${number.format(numeric(transpaVehicleTime.reported_hours))} / ${number.format(numeric(transpaVehicleTime.available_hours))} h · TransPA` : rows ? "Beräknat från importerade underlag" : "Inväntar verifierat underlag"}</small></Link>)}</section>

        {costBreakdown}
        {financeBasis}
        {rows === 0 ? <section className="empty-state"><div className="empty-icon"><FileSpreadsheet size={28}/></div><div><span className="section-kicker">Redo för skarp data</span><h2>Importera första underlaget</h2><p>Dashboarden innehåller ingen demodata. Ladda upp Excel eller PDF för att börja beräkna transportavdelningens nyckeltal.</p></div>{canManage && <Link prefetch={false} className="primary" href={kpiHref("import")}>Öppna dataimport <ChevronRight size={17}/></Link>}</section> : <section className={`detail-grid ${workspaceStyles.wideTable}`}>
          {monthPeriod&&dashboard.economic_units?<KpiEconomicUnits groups={dashboard.group_options??[]} units={dashboard.economic_units} query={periodQuery} totals={{revenue:numeric(metrics.revenue),cost:numeric(metrics.total_cost),result:numeric(metrics.result)}} canManage={canManage}/>:(<article className="panel"><div className="panel-head"><div><span className="section-kicker">Fordon</span><h2>Intäkt och kostnad per fordon</h2></div><Truck size={20}/></div><div className="table-wrap"><table><thead><tr><th>Fordon</th><th>Omsättning</th><th>Omsättning / h</th><th>Personalkostnad</th><th>Kostnad</th><th>Bränsle</th><th>Resultat</th><th>Beläggning</th></tr></thead><tbody>{dashboard.vehicles.map((vehicle) => <tr key={String(vehicle.vehicle)}><td><Link prefetch={false} href={`/kpi/analys?${periodQuery}&vehicle=${encodeURIComponent(vehicle.vehicle === "Ej fördelat" ? "unassigned" : String(vehicle.vehicle))}&level=project`}><strong>{String(vehicle.vehicle)}</strong></Link><small>{vehicle.occupied_hours==null?"Tid ej verifierad för kostnadsstället":`${number.format(numeric(vehicle.occupied_hours))} h TransPA`}</small></td><td>{currency.format(numeric(vehicle.revenue))}</td><td>{vehicle.revenue_per_hour == null ? "–" : `${currency.format(numeric(vehicle.revenue_per_hour))}/h`}</td><td><Link prefetch={false} href={analysisHref(periodQuery,{vehicle:vehicle.vehicle==="Ej fördelat"?"unassigned":String(vehicle.vehicle),category:"personnel",kind:"cost"})}>{currency.format(numeric(vehicle.personnel_cost))}</Link></td><td><Link prefetch={false} href={analysisHref(periodQuery,{vehicle:vehicle.vehicle==="Ej fördelat"?"unassigned":String(vehicle.vehicle),category:null,kind:"cost"})}>{currency.format(numeric(vehicle.cost))}</Link></td><td><Link prefetch={false} href={analysisHref(periodQuery,{vehicle:vehicle.vehicle==="Ej fördelat"?"unassigned":String(vehicle.vehicle),category:"fuel",kind:"cost"})}>{currency.format(numeric(vehicle.fuel_cost))}</Link></td><td><strong>{currency.format(numeric(vehicle.result))}</strong></td><td>{vehicle.utilization == null ? "–" : `${percentDisplay(vehicle.utilization)}`}</td></tr>)}</tbody><tfoot><tr><th>Totalt inklusive Ej fördelat</th><td>{currency.format(numeric(metrics.revenue))}</td><td>–</td><td>–</td><td>{currency.format(numeric(metrics.total_cost))}</td><td>–</td><td><strong>{currency.format(numeric(metrics.result))}</strong></td><td>–</td></tr></tfoot></table></div><p>Ej fördelat ingår i totalen och visar belopp utan fordonskoppling. Inhyrda och släp kan också förekomma som egna rader.</p></article>)}
        </section>}


        <section className="panel"><h2>Verksamhetsgrupper</h2><div className="table-wrap"><table><thead><tr><th>Grupp</th><th>Omsättning</th><th>Kostnad</th><th>Resultat</th></tr></thead><tbody>{dashboard.business_groups?.map(g=><tr key={g.key}><td><Link prefetch={false} href={`/kpi/analys?${periodQuery}&group=${encodeURIComponent(g.key)}&level=unit`}>{g.label}</Link></td><td>{currency.format(g.revenue)}</td><td><Link prefetch={false} href={analysisHref(periodQuery,{group:g.key,unit:null,vehicle:null,project:null,kind:"cost"})}>{currency.format(g.cost)}</Link></td><td>{currency.format(g.result)}</td></tr>)}</tbody></table></div></section>
        <section className="panel imports-panel"><div className="panel-head"><div><span className="section-kicker">Spårbarhet</span><h2>Senaste importer</h2></div>{canManage && <Link prefetch={false} className="secondary" href={kpiHref("import")}><UploadCloud size={16}/>Ny import</Link>}</div>{batches.length ? <div className="table-wrap"><table><thead><tr><th>Fil</th><th>Datatyp</th><th>Period</th><th>Rader</th><th>Status</th></tr></thead><tbody>{batches.map((batch) => <tr key={batch.id}><td><strong>{batch.file_name ?? "API-leverans"}</strong><small>{new Date(batch.created_at).toLocaleString("sv-SE")}</small></td><td>{DATA_KINDS[batch.data_kind]?.label ?? batch.data_kind}</td><td>{batch.period_start ?? "–"} – {batch.period_end ?? "–"}</td><td>{batch.valid_row_count}/{batch.row_count}</td><td><span className={`status-pill ${batch.status}`}>{statusLabel(batch.status)}</span>{["completed", "needs_review"].includes(batch.status) && <ImportReview batchId={batch.id} canManage={canManage} />}</td></tr>)}</tbody></table></div> : <p className="muted-line">Inga importer är genomförda ännu.</p>}</section>
      </div>}

      {view === "import" && <div className="content import-layout">
        {!canManage ? <section className="empty-state"><AlertTriangle size={28}/><div><h2>Du saknar importbehörighet</h2><p>Behörigheten <code>kpi.manage</code> krävs för att lägga in underlag.</p></div></section> : <>
          <section className="panel"><h2>Gemensam import</h2><p>Släpp PDF, Excel eller CSV i samma inkorg. Filerna behandlas en i taget, med kontroll före sparande. Osäkra datatyper väljs manuellt.</p><p>Giltiga transaktioner räknas även om andra rader behöver granskas. Workify-orderexport fördelas enligt artikelregistret: angivet projekt får intäkten, annars utförande fordon. Okända artiklar läggs för granskning.</p><label><input type="checkbox" checked={automatic} disabled={busy} onChange={(event) => { setAutomatic(event.target.checked); setPreview(null); setKindConfirmed(!event.target.checked); }}/> Identifiera datatyp automatiskt</label>{file && <button className="secondary" disabled={busy} onClick={() => { setFile(pendingFiles[0] ?? null); setPendingFiles((current) => current.slice(1)); setPreview(null); setMapping({}); setVehicleRules(""); setKindConfirmed(false); }}>Hoppa över aktuell fil</button>}{pendingFiles.length > 0 && <p>{pendingFiles.length} filer väntar: {pendingFiles.map((item) => item.name).join(", ")}</p>}</section>
          <section className="import-steps"><span className="active">1. Datatyp</span><span className={file ? "active" : ""}>2. Fil</span><span className={preview ? "active" : ""}>3. Kolumnmappning</span><span>4. Import</span></section>
          <section className="panel"><div className="panel-head"><div><span className="section-kicker">Steg 1</span><h2>Välj vilket underlag du importerar</h2></div></div><div className="kind-grid">{(Object.entries(DATA_KINDS) as [DataKind, typeof DATA_KINDS[DataKind]][]).map(([key, item]) => <button className={dataKind === key ? "selected" : ""} key={key} disabled={busy} onClick={() => chooseKind(key)}><span>{item.label}</span><small>{item.description}</small></button>)}</div></section>
          <section className="panel"><div className="panel-head"><div><span className="section-kicker">Steg 2</span><h2>Ladda upp originalfil</h2></div><span className="file-types">PDF · XLSX · XLS · CSV</span></div><label className={`dropzone ${file ? "has-file" : ""}`} onDragOver={(event) => event.preventDefault()} onDrop={(event) => { event.preventDefault(); selectFiles(Array.from(event.dataTransfer.files)); }}><input type="file" multiple disabled={busy} accept=".pdf,.xlsx,.xls,.csv" onChange={(event) => selectFiles(Array.from(event.target.files ?? []))}/><UploadCloud size={30}/>{file ? <><strong>{file.name}</strong><span>{number.format(file.size / 1024)} kB</span></> : <><strong>Välj eller släpp en fil här</strong><span>Originalfilen sparas privat för full spårbarhet. Max 4 MB per fil.</span></>}</label><div className="actions"><button className="primary" disabled={!file || busy} onClick={analyse}>{busy ? "Analyserar…" : "Analysera fil"}</button></div></section>
          {preview && <section className="panel"><h2>Fordonskopplingar för denna import</h2><p>Koppla enhetsnummer eller projektnummer till regnummer. En regel per rad: <code>Kolumnnamn;exakt värde;regnummer</code>. Reglerna gäller endast denna import och sparas med dess underlag. Projekt som avser flera fordon ska inte kopplas till ett enda fordon.</p><textarea disabled={busy} aria-label="Fordonskopplingar" rows={6} style={{ width: "100%", fontFamily: "monospace" }} value={vehicleRules} onChange={(event) => setVehicleRules(event.target.value)} placeholder="Använd ett kolumnnamn från filen;enhetsnummer;regnummer"/><p>Kontrollerade svenska regnummer stöds. Andra beteckningar kräver granskning. Detta verifierar inte permanent Humla Object ID.</p>{batches.some((batch) => batch.column_mapping?.__vehicle_rules) && <label>Återanvänd från tidigare import <select defaultValue="" onChange={(event) => { const previous = batches.find((batch) => batch.id === event.target.value); if (previous) setVehicleRules(previous.column_mapping?.__vehicle_rules ?? ""); }}><option value="">Välj underlag och kontrollera giltigheten</option>{batches.filter((batch) => batch.column_mapping?.__vehicle_rules).map((batch) => <option key={batch.id} value={batch.id}>{batch.file_name}</option>)}</select></label>}{rulePreview.error && <p role="alert">{rulePreview.error}</p>}<div className="table-wrap"><table><thead><tr><th>Fordonsvärde i fil</th><th>Regnummer efter koppling</th><th>Kontroll (första 12 rader)</th></tr></thead><tbody>{rulePreview.rows.map((row, index) => <tr key={index}><td>{row.raw || "–"}</td><td>{row.registration || "Ej kopplad"}</td><td>{row.error ?? (row.registration ? "Entydig koppling" : "Ingen fordonsuppgift")}</td></tr>)}</tbody></table></div></section>}
          {preview && <section className="panel"><div className="panel-head"><div><span className="section-kicker">Steg 3</span><h2>Kontrollera kolumnmappningen</h2></div><span className="row-count">{preview.totalRows} rader hittades</span></div><div className="mapping-grid">{selectedDefinition.fields.map((field) => <label key={field.key}><span>{field.label}{field.required && <b>*</b>}</span><select value={mapping[field.key] ?? ""} onChange={(event) => setMapping((current) => ({ ...current, [field.key]: event.target.value }))}><option value="">Inte mappad</option>{preview.headers.map((header) => <option value={header} key={header}>{header}</option>)}</select></label>)}</div><div className="preview-table"><table><thead><tr>{preview.headers.slice(0,8).map((header) => <th key={header}>{header}</th>)}</tr></thead><tbody>{preview.rows.slice(0,6).map((row, index) => <tr key={index}>{preview.headers.slice(0,8).map((header) => <td key={header}>{row[header] || "–"}</td>)}</tr>)}</tbody></table></div><div className="import-confirm"><div><ShieldCheck size={19}/><p><strong>Fail-closed import</strong><span>Ogiltiga eller osäkert mappade rader påverkar inte nyckeltalen.</span></p></div><button className="primary" disabled={!requiredComplete || !kindConfirmed || !!rulePreview.error || busy} onClick={importFile}>{busy ? "Importerar…" : "Importera och spara"}</button></div></section>}
          {message && <div className={`message ${message.type}`}>{message.type === "success" ? <CheckCircle2 size={18}/> : <AlertTriangle size={18}/>} {message.text}</div>}
        </>}
      </div>}

      {view === "accounts" && <div className="content"><section className="panel"><h2>Konton & kostnader</h2><p>KPI använder de daterade kontoreglerna i Humla Hub. Där styrs kostnadskategori och om kostnaden hör till fordonsresultatet.</p>{canManage ? <Link prefetch={false} className="primary" href={`/kpi/kontrollpanel?${periodQuery}&section=cost`}>Visa och hantera aktuella kontoregler</Link> : <p>En KPI-administratör kan hantera kontoreglerna i Kontrollpanelen.</p>}</section></div>}
      {view === "units" && <div className="content"><form className="period-form"><input type="hidden" name="view" value="units"/><label>Från<input type="date" name="from" defaultValue={from}/></label><label>Till<input type="date" name="to" defaultValue={to}/></label><button>Visa period</button></form>{canManage&&<CompoundUnitBuilder from={from}/>}<UnitManager units={units} report={unitReport} canManage={canManage} from={from} to={to}/></div>}

      {view === "transpa" && canManage && <><TranspaEvidencePanel data={transpaEvidence} from={from} to={to}/>{transpaVehicleTime && <div className="content"><section className="panel"><div className="panel-head"><div><span className="section-kicker">Fordonsbeläggning</span><h2>Rapporterad TransPA-tid per fordon</h2></div><Gauge size={20}/></div><p>{number.format(numeric(transpaVehicleTime.reported_hours))} rapporterade timmar i valt KPI-urval · {number.format(numeric(transpaVehicleTime.available_hours))} tillgängliga timmar.</p><div className="table-wrap"><table><thead><tr><th>Fordon</th><th>TransPA-tid</th><th>Tillgänglig tid</th><th>Beläggning</th><th>Rapporter</th></tr></thead><tbody>{transpaVehicleTime.vehicles?.map((vehicle)=><tr key={vehicle.vehicle_id}><td><strong>{vehicle.vehicle}</strong></td><td>{number.format(numeric(vehicle.occupied_hours))} h</td><td>{number.format(numeric(vehicle.available_hours))} h</td><td><span className="progress"><i style={{width:`${Math.min(numeric(vehicle.utilization),100)}%`}}/></span>{percentDisplay(vehicle.utilization)}</td><td>{vehicle.time_reports}</td></tr>)}</tbody></table></div></section></div>}</>}
      {view === "definitions" && <div className="content definitions-grid">
        <section className="panel"><div className="panel-head"><div><span className="section-kicker">Beräkningsmodell</span><h2>Transportavdelningens sex nyckeltal</h2></div><BarChart3 size={20}/></div><div className="formula-list"><div><strong>Omsättning</strong><code>Σ verifierade intäktsrader</code></div><div><strong>Resultat</strong><code>Omsättning − NEXT-kostnad − TransPA-personal − avskrivning</code></div><div><strong>Intäkt per lastbil</strong><code>Omsättning / intäktsbärande lastbilar</code></div><div><strong>Beläggningsgrad fordon</strong><code>Belagda timmar / tillgängliga timmar</code></div><div><strong>Dieselkostnad</strong><code>Dieselkostnad / omsättning</code></div><div><strong>Debiteringsgrad chaufförer</strong><code>Debiterbara timmar / betalda timmar</code></div></div></section>
        <section className="panel architecture-panel"><div className="panel-head"><div><span className="section-kicker">API-förberedd</span><h2>Samma datakontrakt – ny transportväg</h2></div><Database size={20}/></div><div className="flow"><div><FileSpreadsheet size={20}/><span>PDF / Excel<strong>Manuell import nu</strong></span></div><ChevronRight/><div><Database size={20}/><span>KPI-datakontrakt<strong>Validerad data</strong></span></div><ChevronRight/><div><LayoutDashboard size={20}/><span>Humla Dashboard<strong>Samma beräkningar</strong></span></div></div><p>När respektive API aktiveras ersätter datamotorn filtransporten. Humla Dashboard fortsätter läsa samma normaliserade fält och behöver inte byggas om.</p></section>
        <section className="panel governance"><div><ShieldCheck size={20}/><span><strong>Humla Hub äger reglerna</strong>Beräkningar, klassificeringar och fördelningar ligger i Humla Hub/Supabase.</span></div><div><Database size={20}/><span><strong>Datamotorn äger källdata</strong>API-inhämtning, identitet, provenance och dublettskydd hanteras bakom kulisserna.</span></div></section>
      </div>}
    </main>
  </KpiWorkspace></div>;
}
