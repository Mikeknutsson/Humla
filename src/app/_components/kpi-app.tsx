"use client";

import { ImportReview } from "./import-review";
import { HubReview } from "./hub-review";

import { useEffect, useMemo, useState } from "react";
import {
  BarChart3, CheckCircle2, ChevronRight, Database, FileSpreadsheet, Fuel,
  Gauge, LayoutDashboard, ListTree, Menu, RefreshCw, Settings2, ShieldCheck, Truck,
  UploadCloud, Users, WalletCards, X, AlertTriangle,
} from "lucide-react";
import { DATA_KINDS, suggestMapping, type DataKind, type ParsedRow } from "@/lib/kpi/schema";
import { parseVehicleRules, resolveVehicle } from "@/lib/kpi/vehicle-rules";
import { logout } from "../kpi/login/actions";
import { AccountMappingManager } from "./account-mapping-manager";
import type { AccountMapping } from "@/lib/kpi/account-mapping";
import {TranspaEvidencePanel, type TranspaEvidence} from './transpa-evidence';
import {UnitManager} from './unit-manager';
import type {KpiUnit,UnitReport} from '@/lib/kpi/units';

type Dashboard = {
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

function isoWeek(value: string) {
  const date = new Date(`${value}T00:00:00Z`);
  const day = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  return Math.ceil((((date.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
}

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

export function KpiApp({ dashboard, overviewPrevious, overviewPeriod, overviewWeekly, batches, accountMappings, units, unitReport, transpaEvidence, transpaVehicleTime, efficiency, hiredCapacity, driverProductivity, hubReviews, tenantName, userName, from, to, canManage, initialView = "overview", serverIssues = [] }: {
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
  overviewWeekly: {weeks:Array<{week_start:string;week_end:string;revenue:number;previous_revenue:number}>};
  batches: Batch[];
  accountMappings: AccountMapping[];
  tenantName: string;
  userName: string;
  from: string;
  to: string;
  canManage: boolean;
  initialView?: "overview" | "kpi" | "import" | "definitions" | "accounts" | "units" | "transpa" | "review";
  serverIssues?: string[];
}) {
  const [view] = useState<"overview" | "kpi" | "import" | "definitions" | "accounts" | "units" | "transpa" | "review">(initialView);
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
  const periodQuery = `from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`;
  const kpiHref = (nextView?: string) => `/kpi?${nextView ? `view=${nextView}&` : ""}${periodQuery}`;
  const selectedDate = new Date(`${from}T00:00:00Z`); const selectedFiscalStartYear = selectedDate.getUTCMonth() >= 8 ? selectedDate.getUTCFullYear() : selectedDate.getUTCFullYear() - 1; const fiscalYears = Array.from({ length: 4 }, (_, index) => { const startYear = selectedFiscalStartYear - index; const endYear = startYear + 1; return { label: `${startYear}/${endYear}`, from: `${startYear}-09-01`, to: `${endYear}-08-31` }; });

  const metrics = dashboard.metrics ?? {};
  const rows = numeric(dashboard.quality?.total_rows);
  const currentRevenue = numeric(metrics.revenue);
  const previousRevenue = numeric(overviewPrevious?.metrics?.revenue);
  const currentResult = numeric(metrics.result);
  const previousResult = numeric(overviewPrevious?.metrics?.result);
  const revenueChange = previousRevenue ? (currentRevenue / previousRevenue - 1) * 100 : null;
  const resultMargin = currentRevenue ? currentResult / currentRevenue * 100 : null;
  const previousMargin = previousRevenue ? previousResult / previousRevenue * 100 : null;
  const validRows = numeric(dashboard.quality?.valid_rows);
  const qualityPercent = rows ? validRows / rows * 100 : null;
  const reviewCount = hubReviews.length;
  const costCategories = dashboard.cost_categories ?? {};
  const categoryAmount = (...names: string[]) => Object.entries(costCategories).reduce((sum,[key,value]) => names.some((name) => key.toLocaleLowerCase("sv-SE").includes(name.toLocaleLowerCase("sv-SE"))) ? sum + Math.abs(numeric(value)) : sum, 0);
  const workedHours = numeric(efficiency?.worked_hours);
  const commonCost = categoryAmount("gemensam");
  const overheadCost = categoryAmount("overhead");
  const personnelCost = categoryAmount("personal", "lön");
  const serviceCost = categoryAmount("service", "rep");
  const fixedCost = categoryAmount("fast");
  const fuelCost = Math.abs(numeric(dashboard.components?.fuel_cost));
  const otherCost = Math.abs(numeric(dashboard.components?.other_cost));
  const totalCost = otherCost + fuelCost;
  const directCost = Math.max(0, totalCost - commonCost - overheadCost);
  const hasCostData = totalCost > 0;
  const perHour = (value:number) => hasCostData && workedHours > 0 ? currency.format(value / workedHours) + "/h" : "–";
  const costCards = [
    {label:"Total kostnad / arbetad timme",value:perHour(totalCost),detail:hasCostData?currency.format(totalCost)+" total kostnad":"Inväntar kostnadsdata"},
    {label:"Direkt kostnad / arbetad timme",value:perHour(directCost),detail:hasCostData?"Exkl. identifierat gemensamt och overhead":"Inväntar kostnadsdata"},
    {label:"Gemensamma kostnader",value:hasCostData?currency.format(commonCost):"–",detail:commonCost>0?"Identifierat som gemensam kostnad":"Inväntar klassificerade gemensamma kostnader"},
    {label:"Gemensamt / arbetad timme",value:commonCost>0&&workedHours>0?currency.format(commonCost/workedHours)+"/h":"–",detail:commonCost>0?"Gemensamma kostnader / TransPA-timmar":"Inväntar gemensamma kostnader"},
    {label:"Overhead / arbetad timme",value:overheadCost>0&&workedHours>0?currency.format(overheadCost/workedHours)+"/h":"–",detail:overheadCost>0?currency.format(overheadCost)+" overhead":"Inväntar overheadklassificering"},
    {label:"Personalkostnad / arbetad timme",value:personnelCost>0&&workedHours>0?currency.format(personnelCost/workedHours)+"/h":"–",detail:personnelCost>0?currency.format(personnelCost):"Inväntar lönekostnad"},
    {label:"Bränsle / arbetad timme",value:fuelCost>0&&workedHours>0?currency.format(fuelCost/workedHours)+"/h":"–",detail:fuelCost>0?currency.format(fuelCost):"Inväntar bränslekostnad"},
    {label:"Service & rep. / arbetad timme",value:serviceCost>0&&workedHours>0?currency.format(serviceCost/workedHours)+"/h":"–",detail:serviceCost>0?currency.format(serviceCost):"Inväntar kostnadsdata"},
    {label:"Fasta kostnader / arbetad timme",value:fixedCost>0&&workedHours>0?currency.format(fixedCost/workedHours)+"/h":"–",detail:fixedCost>0?currency.format(fixedCost):"Inväntar kostnadsdata"},
    {label:"TB / arbetad timme",value:hasCostData&&workedHours>0?currency.format((currentRevenue-directCost)/workedHours)+"/h":"–",detail:"Omsättning minus direkt kostnad"},
    {label:"Resultat / arbetad timme",value:hasCostData&&workedHours>0?currency.format(currentResult/workedHours)+"/h":"–",detail:"Resultat / TransPA-timmar"},
  ];
  const vehicleCount = numeric(transpaVehicleTime?.vehicle_count);
  const reportedHours = numeric(transpaVehicleTime?.reported_hours);
  const availableHours = numeric(transpaVehicleTime?.available_hours);
  const utilization = numeric(transpaVehicleTime?.utilization ?? metrics.vehicle_utilization);
  const hiredShare = numeric(hiredCapacity?.hired_share_percent);
  const productivePercent = numeric(driverProductivity?.productive_percent);
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
  const metricCards = [
    { label: "Omsättning", value: currency.format(numeric(metrics.revenue)), icon: WalletCards, tone: "yellow" },
    { label: "Resultat", value: currency.format(numeric(metrics.result)), icon: BarChart3, tone: numeric(metrics.result) >= 0 ? "green" : "red" },
    { label: "Intäkt per lastbil", value: currency.format(numeric(metrics.revenue_per_vehicle)), icon: Truck, tone: "blue" },
    { label: "Omsättning / arbetad timme", value: efficiency?.revenue_per_worked_hour != null ? `${currency.format(numeric(efficiency.revenue_per_worked_hour))}/h` : "–", icon: Gauge, tone: "green", detail: `${currency.format(numeric(efficiency?.own_revenue))} egen omsättning · UE/LASTBIL exkluderad` },
    { label: "Beläggningsgrad fordon", value: `${number.format(numeric(transpaVehicleTime?.utilization ?? metrics.vehicle_utilization))} %`, icon: Gauge, tone: "purple" },
    { label: "Inhyrd kapacitet", value: `${number.format(numeric(hiredCapacity?.hired_share_percent))} %`, icon: Truck, tone: "orange", detail: `${currency.format(numeric(hiredCapacity?.hired_revenue))} av ${currency.format(numeric(hiredCapacity?.total_revenue))}` },
    { label: "Dieselkostnad av omsättning", value: `${number.format(numeric(metrics.diesel_share))} %`, icon: Fuel, tone: "orange" },
    { label: "Intäktskopplad tid chaufför", value: `${number.format(numeric(driverProductivity?.productive_percent))} %`, icon: Users, tone: "cyan", detail: `${number.format(numeric(driverProductivity?.productive_hours))} h av ${number.format(numeric(driverProductivity?.total_hours))} h · ${number.format(numeric(driverProductivity?.unclassified_hours))} h oklassificerat` },
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
        setMessage({ type: "info", text: "Humla kunde inte avgöra datatypen säkert. Välj källa/datatype för filen; oklara rader hanteras separat och stoppar inte övriga rader." });
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

  return <div className="kpi-app"><div className="app-shell">
    <aside className={`sidebar ${mobileMenu ? "open" : ""}`}>
      <div className="brand-wrap"><div className="brand-mark">H</div><div><div className="brand">Humla</div><div className="brand-sub">DASHBOARD</div></div><button className="icon-button close-nav" onClick={() => setMobileMenu(false)} aria-label="Stäng meny"><X size={18}/></button></div>
      <div className="workspace"><span>Arbetsyta</span><strong>{tenantName}</strong></div>
      <nav className="nav">
        <a className={view === "overview" ? "active" : ""} href={kpiHref()} onClick={() => setMobileMenu(false)}><LayoutDashboard size={18}/>Dashboard</a>
        <a className={view === "kpi" ? "active" : ""} href={kpiHref("kpi")} onClick={() => setMobileMenu(false)}><BarChart3 size={18}/>KPI</a>
        <a className={view === "import" ? "active" : ""} href={kpiHref("import")} onClick={() => setMobileMenu(false)}><UploadCloud size={18}/>Dataimport</a>
        {canManage&&<div className="nav-group"><span className="nav-group-title"><Settings2 size={15}/>Inställningar</span>
          <a className={view === "review" ? "active" : ""} href={kpiHref("review")} onClick={() => setMobileMenu(false)}><CheckCircle2 size={17}/>Granskning & mappning</a>
          <a className={view === "accounts" ? "active" : ""} href={kpiHref("accounts")} onClick={() => setMobileMenu(false)}><ListTree size={17}/>Kontomappning</a>
          <a className={view === "units" ? "active" : ""} href={kpiHref("units")} onClick={() => setMobileMenu(false)}><Truck size={17}/>Enhetsmappning</a>
          <a className={view === "transpa" ? "active" : ""} href={kpiHref("transpa")} onClick={() => setMobileMenu(false)}><Database size={17}/>TransPA-underlag</a>
          <a className={view === "definitions" ? "active" : ""} href={kpiHref("definitions")} onClick={() => setMobileMenu(false)}><Settings2 size={17}/>KPI-definitioner</a>
        </div>}
      </nav>
      <div className="sidebar-status"><div className="status-icon"><Database size={17}/></div><div><strong>Datamotor</strong><span>Ansluten</span></div><span className="live-dot"/></div>
      <div className="user-block"><div className="avatar">{userName.split(" ").map((part) => part[0]).join("").slice(0,2)}</div><div><strong>{userName}</strong><span>KPI-användare</span></div><form action={logout}><button className="logout-button" type="submit">Logga ut</button></form></div>
    </aside>

    <main className="app-main">
      <header className="topbar"><button className="icon-button mobile-nav" onClick={() => setMobileMenu(true)} aria-label="Öppna meny"><Menu size={20}/></button><div><span className="breadcrumb">Humla Dashboard / Transport</span><h1>{view === "overview" ? "Dashboard" : view === "kpi" ? "KPI – Transport" : view === "import" ? "Dataimport" : view === "review" ? "Granskning & mappning" : view === "accounts" ? "Kontomappning" : view === "units" ? "Enhetsmappning" : view === "transpa" ? "TransPA-underlag" : "KPI-definitioner"}</h1></div><div className="topbar-badge"><ShieldCheck size={16}/>Säker KPI-arbetsyta</div></header>
      {serverIssues.length > 0 && <div className="content server-issues"><AlertTriangle size={18}/><div><strong>En del data kunde inte hämtas</strong><span>{serverIssues.join(" · ")}</span></div></div>}

      {view === "review" && <div className="content"><HubReview initial={hubReviews as never[]}/></div>}
      {view === "overview" && <div className="content">
        <section className="overview-hero"><div><span className="section-kicker">Verksamhetsår {overviewPeriod.label}</span><h2>Översikt t.o.m. {overviewPeriod.current.to}</h2><p>Jämför {overviewPeriod.current.from} – {overviewPeriod.current.to} med samma antal dagar föregående verksamhetsår.</p></div><span className="asof">Senaste kompletta dag</span></section>
        <section className="overview-pulse"><a href={kpiHref("kpi")}><span>Omsättning YTD</span><strong>{currency.format(currentRevenue)}</strong><small>{revenueChange == null ? "Jämförelse saknas" : `${revenueChange >= 0 ? "+" : ""}${number.format(revenueChange)} % mot fg. år`}</small></a><a href={kpiHref("kpi")}><span>Resultatmarginal</span><strong>{resultMargin == null ? "–" : `${number.format(resultMargin)} %`}</strong><small>{previousMargin == null ? "Fg. år saknas" : `Fg. år ${number.format(previousMargin)} %`}</small></a><a href={kpiHref("review")}><span>Behöver granskas</span><strong>{reviewCount}</strong><small>{reviewCount ? "Öppna avvikelser" : "Inga öppna granskningsfall"}</small></a><a href={kpiHref("review")}><span>Datatäckning</span><strong>{qualityPercent == null ? "–" : `${number.format(qualityPercent)} %`}</strong><small>{number.format(validRows)} av {number.format(rows)} rader</small></a></section>
        <section className="metrics-grid">{metricCards.slice(0,6).map(({label,value,icon:Icon,tone,detail})=>{const prev=numeric(overviewPrevious?.metrics?.[label==="Omsättning"?"revenue":label==="Resultat"?"result":""]);const current=label==="Omsättning"?numeric(metrics.revenue):label==="Resultat"?numeric(metrics.result):0;const change=prev&&current?(current/prev-1)*100:null;return <a className="metric-card overview-card" href={kpiHref("kpi")} key={label}><div className={`metric-icon ${tone}`}><Icon size={20}/></div><span>{label}</span><strong>{value}</strong><small>{change!=null?`${change>=0?"+":""}${number.format(change)} % mot fg. år`:detail??"Öppna KPI för analys"}</small></a>})}</section>
        <section className="overview-operations"><div className="panel"><div className="panel-head"><div><span className="section-kicker">Drift & fordon</span><h2>Kapacitet och nyttjande</h2></div></div><div className="mini-kpi-grid"><a href={kpiHref("kpi")}><span>Beläggningsgrad</span><strong>{number.format(utilization)} %</strong><small>{number.format(reportedHours)} av {number.format(availableHours)} h</small></a><a href={kpiHref("kpi")}><span>Fordon i underlaget</span><strong>{number.format(vehicleCount)}</strong><small>Fordon med TransPA-tid</small></a><a href={kpiHref("kpi")}><span>Inhyrd kapacitet</span><strong>{number.format(hiredShare)} %</strong><small>{currency.format(numeric(hiredCapacity?.hired_revenue))} omsättning</small></a><a href={kpiHref("kpi")}><span>Intäkt / lastbil</span><strong>{currency.format(numeric(metrics.revenue_per_vehicle))}</strong><small>För vald period</small></a></div></div><div className="panel"><div className="panel-head"><div><span className="section-kicker">Personal & kapacitet</span><h2>Arbetad och intäktskopplad tid</h2></div></div><div className="mini-kpi-grid"><a href={kpiHref("kpi")}><span>Arbetad tid</span><strong>{number.format(reportedHours)} h</strong><small>Rapporterad fordonstid</small></a><a href={kpiHref("kpi")}><span>Intäktskopplad tid</span><strong>{number.format(productivePercent)} %</strong><small>{number.format(productiveHours)} h</small></a><a href={kpiHref("kpi")}><span>Oklassificerad tid</span><strong>{number.format(unclassifiedHours)} h</strong><small>Saknar intäktskoppling</small></a><a href={kpiHref("kpi")}><span>Omsättning / timme</span><strong>{efficiency?.revenue_per_worked_hour!=null ? currency.format(numeric(efficiency.revenue_per_worked_hour))+"/h" : "–"}</strong><small>Egen omsättning / TransPA-tid</small></a></div></div></section>
        <section className="panel attention-panel"><div className="panel-head"><div><span className="section-kicker">Uppmärksamhet</span><h2>Datapunkter som kräver åtgärd</h2></div><strong>{attentionItems.length || "Inga"}</strong></div>{attentionItems.length ? <div className="attention-grid">{attentionItems.map((item)=><a href={item.href} key={item.label}><span>{item.label}</span><strong>{item.value}</strong><small>{item.detail}</small></a>)}</div> : <p className="attention-empty">Inga identifierade datakvalitetsavvikelser i vald period.</p>}</section>
        <section className="panel cost-efficiency-panel"><div className="panel-head"><div><span className="section-kicker">Kostnad & effektivitet</span><h2>Kostnad per arbetad timme</h2></div><small>{workedHours>0?`${number.format(workedHours)} arbetade timmar i underlaget`:"Inväntar TransPA-tid"}</small></div><div className="cost-kpi-grid">{costCards.map((item)=><a href={kpiHref("kpi")} className="cost-kpi" key={item.label}><span>{item.label}</span><strong>{item.value}</strong><small>{item.detail}</small></a>)}</div></section>
                <section className="panel weekly-panel"><div className="panel-head"><div><span className="section-kicker">Löpande vecka</span><h2>Omsättning per vecka</h2></div><small>Aktuellt år mot föregående år</small></div><div className="weekly-chart">{(overviewWeekly?.weeks??[]).map((w,i)=>{const max=Math.max(...(overviewWeekly?.weeks??[]).flatMap(x=>[numeric(x.revenue),numeric(x.previous_revenue)]),1);return <div className="week-column" key={w.week_start}><div className="bars"><i title={currency.format(numeric(w.previous_revenue))} style={{height:`${Math.max(3,numeric(w.previous_revenue)/max*100)}%`}}/><b title={currency.format(numeric(w.revenue))} style={{height:`${Math.max(3,numeric(w.revenue)/max*100)}%`}}/></div><span>v{isoWeek(w.week_start)}</span></div>})}</div><div className="chart-legend"><span><i/>Föregående år</span><span><b/>Aktuellt år</span></div></section>
        <section className="overview-grid"><article className="panel"><div className="panel-head"><div><span className="section-kicker">Jämförelse</span><h2>YTD mot föregående verksamhetsår</h2></div></div><div className="ytd-bars"><div><span>Omsättning</span><strong>{currency.format(currentRevenue)}</strong><small>Fg. år {currency.format(previousRevenue)}{revenueChange != null ? ` · ${revenueChange >= 0 ? "+" : ""}${number.format(revenueChange)} %` : ""}</small></div><div><span>Resultat</span><strong>{currency.format(currentResult)}</strong><small>Fg. år {currency.format(previousResult)}</small></div><div><span>Resultatmarginal</span><strong>{resultMargin == null ? "–" : `${number.format(resultMargin)} %`}</strong><small>{previousMargin == null ? "Fg. år saknas" : `Fg. år ${number.format(previousMargin)} %`}</small></div></div></article><article className="panel"><div className="panel-head"><div><span className="section-kicker">Snabbläge</span><h2>Datakvalitet</h2></div></div><p>{numeric(dashboard.quality.valid_rows)} giltiga rader · {numeric(dashboard.quality.rows_without_vehicle)} utan fordonskoppling · {numeric(dashboard.quality.rows_without_employee)} utan chaufförskoppling.</p><a className="quality-link" href={kpiHref("review")}>Öppna granskning <ChevronRight size={14}/></a></article></section>
      </div>}
      {view === "kpi" && <div className="content">
        <section className="period-bar"><div><span className="section-kicker">Rapportperiod</span><strong>{from} – {to}</strong><div className="period-shortcuts">{fiscalYears.map((year) => <a key={year.label} className={from === year.from && to === year.to ? "active" : ""} href={`/kpi?${view === "kpi" ? "view=kpi&" : ""}from=${year.from}&to=${year.to}`}>{year.label}</a>)}</div></div><form className="period-form">{view === "kpi" && <input type="hidden" name="view" value="kpi"/>}<label>Från<input type="date" name="from" defaultValue={from}/></label><label>Till<input type="date" name="to" defaultValue={to}/></label><button type="submit"><RefreshCw size={15}/>Uppdatera</button></form></section>

        <section className="metrics-grid">{metricCards.map(({ label, value, icon: Icon, tone, detail }) => <a className="metric-card" href={`${kpiHref("kpi")}&metric=${encodeURIComponent(label)}`} key={label}><div className={`metric-icon ${tone}`}><Icon size={20}/></div><span>{label}</span><strong>{value}</strong><small>{detail ? detail : label === "Beläggningsgrad fordon" && transpaVehicleTime?.reported_hours ? `${number.format(numeric(transpaVehicleTime.reported_hours))} / ${number.format(numeric(transpaVehicleTime.available_hours))} h · TransPA` : rows ? "Beräknat från importerade underlag" : "Inväntar verifierat underlag"}</small></a>)}</section>

        {rows === 0 ? <section className="empty-state"><div className="empty-icon"><FileSpreadsheet size={28}/></div><div><span className="section-kicker">Redo för skarp data</span><h2>Importera första underlaget</h2><p>Dashboarden innehåller ingen demodata. Ladda upp Excel eller PDF för att börja beräkna transportavdelningens nyckeltal.</p></div>{canManage && <a className="primary" href={kpiHref("import")}>Öppna dataimport <ChevronRight size={17}/></a>}</section> : <section className="detail-grid">
          <article className="panel"><div className="panel-head"><div><span className="section-kicker">Fordon</span><h2>Intäkt och nyttjande per lastbil</h2></div><Truck size={20}/></div><div className="table-wrap"><table><thead><tr><th>Fordon</th><th>Omsättning</th><th>Omsättning / h</th><th>Kostnad</th><th>Diesel</th><th>Beläggning</th></tr></thead><tbody>{dashboard.vehicles.map((vehicle) => { const transpa = transpaVehicleTime?.vehicles?.find((item) => item.vehicle === String(vehicle.vehicle)); const available = transpa ? numeric(transpa.available_hours) : numeric(vehicle.available_hours); const occupied = transpa ? numeric(transpa.occupied_hours) : numeric(vehicle.occupied_hours); const utilization = available ? occupied / available * 100 : 0; return <tr key={String(vehicle.vehicle)}><td><strong>{String(vehicle.vehicle)}</strong>{transpa && <small>{number.format(occupied)} h TransPA</small>}</td><td>{currency.format(numeric(vehicle.revenue))}</td><td>{String(vehicle.vehicle).trim().toUpperCase() === "LASTBIL" || !transpa || occupied <= 0 ? "–" : `${currency.format(numeric(vehicle.revenue) / occupied)}/h`}</td><td>{currency.format(numeric(vehicle.cost))}</td><td>{currency.format(numeric(vehicle.fuel_cost))}</td><td><span className="progress"><i style={{ width: `${Math.min(utilization,100)}%` }}/></span>{number.format(utilization)} %</td></tr>; })}</tbody></table></div></article>
          <article className="panel quality-panel"><div className="panel-head"><div><span className="section-kicker">Datakvalitet</span><h2>Underlagets täckning</h2></div><ShieldCheck size={20}/></div><div className="quality-score"><strong>{numeric(dashboard.quality.valid_rows)}</strong><span>giltiga rader av {numeric(dashboard.quality.total_rows)}</span></div><ul><li><span>Ej mappade kontorader</span><strong>{numeric(dashboard.quality.rows_without_account_mapping)}</strong></li><li><span>Rader utan fordonskoppling</span><strong>{numeric(dashboard.quality.rows_without_vehicle)}</strong></li><li><span>Rader utan chaufförskoppling</span><strong>{numeric(dashboard.quality.rows_without_employee)}</strong></li><li><span>Importer i perioden</span><strong>{batches.length}</strong></li></ul>{numeric(dashboard.quality.rows_without_account_mapping) > 0 && <a className="quality-link" href={kpiHref("accounts")}>Öppna Ej mappade konton <ChevronRight size={14}/></a>}</article>
        </section>}

        <section className="panel imports-panel"><div className="panel-head"><div><span className="section-kicker">Spårbarhet</span><h2>Senaste importer</h2></div>{canManage && <a className="secondary" href={kpiHref("import")}><UploadCloud size={16}/>Ny import</a>}</div>{batches.length ? <div className="table-wrap"><table><thead><tr><th>Fil</th><th>Datatyp</th><th>Period</th><th>Rader</th><th>Status</th></tr></thead><tbody>{batches.map((batch) => <tr key={batch.id}><td><strong>{batch.file_name ?? "API-leverans"}</strong><small>{new Date(batch.created_at).toLocaleString("sv-SE")}</small></td><td>{DATA_KINDS[batch.data_kind]?.label ?? batch.data_kind}</td><td>{batch.period_start ?? "–"} – {batch.period_end ?? "–"}</td><td>{batch.valid_row_count}/{batch.row_count}</td><td><span className={`status-pill ${batch.status}`}>{statusLabel(batch.status)}</span>{["completed", "needs_review"].includes(batch.status) && <ImportReview batchId={batch.id} canManage={canManage} />}</td></tr>)}</tbody></table></div> : <p className="muted-line">Inga importer är genomförda ännu.</p>}</section>
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

      {view === "accounts" && <div className="content"><AccountMappingManager mappings={accountMappings} unmapped={dashboard.unmapped_accounts ?? []} canManage={canManage}/></div>}
      {view === "units" && <div className="content"><form className="period-form"><input type="hidden" name="view" value="units"/><label>Från<input type="date" name="from" defaultValue={from}/></label><label>Till<input type="date" name="to" defaultValue={to}/></label><button>Visa period</button></form><UnitManager units={units} report={unitReport} canManage={canManage} from={from} to={to}/></div>}

      {view === "transpa" && canManage && <><TranspaEvidencePanel data={transpaEvidence} from={from} to={to}/>{transpaVehicleTime && <div className="content"><section className="panel"><div className="panel-head"><div><span className="section-kicker">Fordonsbeläggning</span><h2>Rapporterad TransPA-tid per fordon</h2></div><Gauge size={20}/></div><p>{number.format(numeric(transpaVehicleTime.reported_hours))} rapporterade timmar · kapacitet {number.format(numeric(transpaVehicleTime.capacity_hours_per_day))} h per vardag.</p><div className="table-wrap"><table><thead><tr><th>Fordon</th><th>TransPA-tid</th><th>Tillgänglig tid</th><th>Beläggning</th><th>Rapporter</th></tr></thead><tbody>{transpaVehicleTime.vehicles?.map((vehicle)=><tr key={vehicle.vehicle_id}><td><strong>{vehicle.vehicle}</strong></td><td>{number.format(numeric(vehicle.occupied_hours))} h</td><td>{number.format(numeric(vehicle.available_hours))} h</td><td><span className="progress"><i style={{width:`${Math.min(numeric(vehicle.utilization),100)}%`}}/></span>{number.format(numeric(vehicle.utilization))} %</td><td>{vehicle.time_reports}</td></tr>)}</tbody></table></div></section></div>}</>}
      {view === "definitions" && <div className="content definitions-grid">
        <section className="panel"><div className="panel-head"><div><span className="section-kicker">Beräkningsmodell</span><h2>Transportavdelningens sex nyckeltal</h2></div><BarChart3 size={20}/></div><div className="formula-list"><div><strong>Omsättning</strong><code>Σ verifierade intäktsrader</code></div><div><strong>Resultat</strong><code>Omsättning − övriga kostnader − diesel</code></div><div><strong>Intäkt per lastbil</strong><code>Omsättning / intäktsbärande lastbilar</code></div><div><strong>Beläggningsgrad fordon</strong><code>Belagda timmar / tillgängliga timmar</code></div><div><strong>Dieselkostnad</strong><code>Dieselkostnad / omsättning</code></div><div><strong>Debiteringsgrad chaufförer</strong><code>Debiterbara timmar / betalda timmar</code></div></div></section>
        <section className="panel architecture-panel"><div className="panel-head"><div><span className="section-kicker">API-förberedd</span><h2>Samma datakontrakt – ny transportväg</h2></div><Database size={20}/></div><div className="flow"><div><FileSpreadsheet size={20}/><span>PDF / Excel<strong>Manuell import nu</strong></span></div><ChevronRight/><div><Database size={20}/><span>KPI-datakontrakt<strong>Validerad data</strong></span></div><ChevronRight/><div><LayoutDashboard size={20}/><span>Humla Dashboard<strong>Samma beräkningar</strong></span></div></div><p>När respektive API aktiveras ersätter datamotorn filtransporten. Humla Dashboard fortsätter läsa samma normaliserade fält och behöver inte byggas om.</p></section>
        <section className="panel governance"><div><ShieldCheck size={20}/><span><strong>KPI äger reglerna</strong>Definitioner, mål och fördelningar ligger i KPI-appen.</span></div><div><Database size={20}/><span><strong>Datamotorn äger källdata</strong>API-inhämtning, identitet, provenance och dublettskydd hanteras bakom kulisserna.</span></div></section>
      </div>}
    </main>
  </div></div>;
}
