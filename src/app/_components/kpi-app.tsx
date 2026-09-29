"use client";

import { useMemo, useState } from "react";
import {
  BarChart3, CheckCircle2, ChevronRight, Database, FileSpreadsheet, Fuel,
  Gauge, LayoutDashboard, Menu, RefreshCw, Settings2, ShieldCheck, Truck,
  UploadCloud, Users, WalletCards, X, AlertTriangle,
} from "lucide-react";
import { DATA_KINDS, type DataKind, type ParsedRow } from "@/lib/kpi/schema";
import { logout } from "../kpi/login/actions";

type Dashboard = {
  metrics: Record<string, number | string>;
  components: Record<string, number | string>;
  vehicles: Array<Record<string, number | string>>;
  drivers: Array<Record<string, number | string>>;
  quality: Record<string, number | string>;
};

type Batch = {
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

export function KpiApp({ dashboard, batches, tenantName, userName, from, to, canManage, initialView = "overview", serverIssues = [] }: {
  dashboard: Dashboard;
  batches: Batch[];
  tenantName: string;
  userName: string;
  from: string;
  to: string;
  canManage: boolean;
  initialView?: "overview" | "import" | "definitions";
  serverIssues?: string[];
}) {
  const [view] = useState<"overview" | "import" | "definitions">(initialView);
  const [mobileMenu, setMobileMenu] = useState(false);
  const [dataKind, setDataKind] = useState<DataKind>("revenue");
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [mapping, setMapping] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ type: "error" | "success"; text: string } | null>(null);

  const metrics = dashboard.metrics ?? {};
  const rows = numeric(dashboard.quality?.total_rows);
  const metricCards = [
    { label: "Omsättning", value: currency.format(numeric(metrics.revenue)), icon: WalletCards, tone: "yellow" },
    { label: "Resultat", value: currency.format(numeric(metrics.result)), icon: BarChart3, tone: numeric(metrics.result) >= 0 ? "green" : "red" },
    { label: "Intäkt per lastbil", value: currency.format(numeric(metrics.revenue_per_vehicle)), icon: Truck, tone: "blue" },
    { label: "Beläggningsgrad fordon", value: `${number.format(numeric(metrics.vehicle_utilization))} %`, icon: Gauge, tone: "purple" },
    { label: "Dieselkostnad av omsättning", value: `${number.format(numeric(metrics.diesel_share))} %`, icon: Fuel, tone: "orange" },
    { label: "Debiteringsgrad chaufförer", value: `${number.format(numeric(metrics.driver_billability))} %`, icon: Users, tone: "cyan" },
  ];

  const selectedDefinition = DATA_KINDS[dataKind];
  const requiredComplete = useMemo(() => selectedDefinition.fields.filter((field) => field.required).every((field) => mapping[field.key]), [mapping, selectedDefinition]);

  async function analyse() {
    if (!file) return;
    setBusy(true);
    setMessage(null);
    const body = new FormData();
    body.set("file", file);
    body.set("dataKind", dataKind);
    try {
      const response = await fetch("/api/kpi/parse", { method: "POST", body });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Filen kunde inte analyseras.");
      setPreview(result);
      setMapping(result.suggestedMapping);
    } catch (error) {
      setMessage({ type: "error", text: error instanceof Error ? error.message : "Filen kunde inte analyseras." });
    } finally {
      setBusy(false);
    }
  }

  async function importFile() {
    if (!file || !preview || !requiredComplete) return;
    setBusy(true);
    setMessage(null);
    const body = new FormData();
    body.set("file", file);
    body.set("dataKind", dataKind);
    body.set("mapping", JSON.stringify(mapping));
    try {
      const response = await fetch("/api/kpi/import", { method: "POST", body });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Importen misslyckades.");
      setMessage({ type: "success", text: `${result.validRows} av ${result.rows} rader importerades och sparades.` });
      setTimeout(() => window.location.reload(), 900);
    } catch (error) {
      setMessage({ type: "error", text: error instanceof Error ? error.message : "Importen misslyckades." });
    } finally {
      setBusy(false);
    }
  }

  function chooseKind(next: DataKind) {
    setDataKind(next);
    setPreview(null);
    setMapping({});
    setMessage(null);
  }

  return <div className="kpi-app"><div className="app-shell">
    <aside className={`sidebar ${mobileMenu ? "open" : ""}`}>
      <div className="brand-wrap"><div className="brand-mark">H</div><div><div className="brand">Humla</div><div className="brand-sub">KPI</div></div><button className="icon-button close-nav" onClick={() => setMobileMenu(false)} aria-label="Stäng meny"><X size={18}/></button></div>
      <div className="workspace"><span>Arbetsyta</span><strong>{tenantName}</strong></div>
      <nav className="nav">
        <a className={view === "overview" ? "active" : ""} href="/kpi" onClick={() => setMobileMenu(false)}><LayoutDashboard size={18}/>Översikt</a>
        <a className={view === "import" ? "active" : ""} href="/kpi?view=import" onClick={() => setMobileMenu(false)}><UploadCloud size={18}/>Dataimport</a>
        <a className={view === "definitions" ? "active" : ""} href="/kpi?view=definitions" onClick={() => setMobileMenu(false)}><Settings2 size={18}/>Definitioner</a>
      </nav>
      <div className="sidebar-status"><div className="status-icon"><Database size={17}/></div><div><strong>Datamotor</strong><span>Ansluten</span></div><span className="live-dot"/></div>
      <div className="user-block"><div className="avatar">{userName.split(" ").map((part) => part[0]).join("").slice(0,2)}</div><div><strong>{userName}</strong><span>KPI-användare</span></div><form action={logout}><button className="logout-button" type="submit">Logga ut</button></form></div>
    </aside>

    <main className="app-main">
      <header className="topbar"><button className="icon-button mobile-nav" onClick={() => setMobileMenu(true)} aria-label="Öppna meny"><Menu size={20}/></button><div><span className="breadcrumb">KPI / Transport</span><h1>{view === "overview" ? "Transportstyrning" : view === "import" ? "Dataimport" : "KPI-definitioner"}</h1></div><div className="topbar-badge"><ShieldCheck size={16}/>Säker KPI-arbetsyta</div></header>
      {serverIssues.length > 0 && <div className="content server-issues"><AlertTriangle size={18}/><div><strong>En del data kunde inte hämtas</strong><span>{serverIssues.join(" · ")}</span></div></div>}

      {view === "overview" && <div className="content">
        <section className="period-bar"><div><span className="section-kicker">Rapportperiod</span><strong>{from} – {to}</strong></div><form className="period-form"><label>Från<input type="date" name="from" defaultValue={from}/></label><label>Till<input type="date" name="to" defaultValue={to}/></label><button type="submit"><RefreshCw size={15}/>Uppdatera</button></form></section>

        <section className="metrics-grid">{metricCards.map(({ label, value, icon: Icon, tone }) => <article className="metric-card" key={label}><div className={`metric-icon ${tone}`}><Icon size={20}/></div><span>{label}</span><strong>{value}</strong><small>{rows ? "Beräknat från importerade underlag" : "Inväntar verifierat underlag"}</small></article>)}</section>

        {rows === 0 ? <section className="empty-state"><div className="empty-icon"><FileSpreadsheet size={28}/></div><div><span className="section-kicker">Redo för skarp data</span><h2>Importera första underlaget</h2><p>Dashboarden innehåller ingen demodata. Ladda upp Excel eller PDF för att börja beräkna transportavdelningens nyckeltal.</p></div>{canManage && <a className="primary" href="/kpi?view=import">Öppna dataimport <ChevronRight size={17}/></a>}</section> : <section className="detail-grid">
          <article className="panel"><div className="panel-head"><div><span className="section-kicker">Fordon</span><h2>Intäkt och nyttjande per lastbil</h2></div><Truck size={20}/></div><div className="table-wrap"><table><thead><tr><th>Fordon</th><th>Omsättning</th><th>Kostnad</th><th>Diesel</th><th>Beläggning</th></tr></thead><tbody>{dashboard.vehicles.map((vehicle) => { const available = numeric(vehicle.available_hours); const utilization = available ? numeric(vehicle.occupied_hours) / available * 100 : 0; return <tr key={String(vehicle.vehicle)}><td><strong>{String(vehicle.vehicle)}</strong></td><td>{currency.format(numeric(vehicle.revenue))}</td><td>{currency.format(numeric(vehicle.cost))}</td><td>{currency.format(numeric(vehicle.fuel_cost))}</td><td><span className="progress"><i style={{ width: `${Math.min(utilization,100)}%` }}/></span>{number.format(utilization)} %</td></tr>; })}</tbody></table></div></article>
          <article className="panel quality-panel"><div className="panel-head"><div><span className="section-kicker">Datakvalitet</span><h2>Underlagets täckning</h2></div><ShieldCheck size={20}/></div><div className="quality-score"><strong>{numeric(dashboard.quality.valid_rows)}</strong><span>giltiga rader av {numeric(dashboard.quality.total_rows)}</span></div><ul><li><span>Rader utan fordonskoppling</span><strong>{numeric(dashboard.quality.rows_without_vehicle)}</strong></li><li><span>Rader utan chaufförskoppling</span><strong>{numeric(dashboard.quality.rows_without_employee)}</strong></li><li><span>Importer i perioden</span><strong>{batches.length}</strong></li></ul></article>
        </section>}

        <section className="panel imports-panel"><div className="panel-head"><div><span className="section-kicker">Spårbarhet</span><h2>Senaste importer</h2></div>{canManage && <a className="secondary" href="/kpi?view=import"><UploadCloud size={16}/>Ny import</a>}</div>{batches.length ? <div className="table-wrap"><table><thead><tr><th>Fil</th><th>Datatyp</th><th>Period</th><th>Rader</th><th>Status</th></tr></thead><tbody>{batches.map((batch) => <tr key={batch.id}><td><strong>{batch.file_name ?? "API-leverans"}</strong><small>{new Date(batch.created_at).toLocaleString("sv-SE")}</small></td><td>{DATA_KINDS[batch.data_kind]?.label ?? batch.data_kind}</td><td>{batch.period_start ?? "–"} – {batch.period_end ?? "–"}</td><td>{batch.valid_row_count}/{batch.row_count}</td><td><span className={`status-pill ${batch.status}`}>{statusLabel(batch.status)}</span></td></tr>)}</tbody></table></div> : <p className="muted-line">Inga importer är genomförda ännu.</p>}</section>
      </div>}

      {view === "import" && <div className="content import-layout">
        {!canManage ? <section className="empty-state"><AlertTriangle size={28}/><div><h2>Du saknar importbehörighet</h2><p>Behörigheten <code>kpi.manage</code> krävs för att lägga in underlag.</p></div></section> : <>
          <section className="import-steps"><span className="active">1. Datatyp</span><span className={file ? "active" : ""}>2. Fil</span><span className={preview ? "active" : ""}>3. Kolumnmappning</span><span>4. Import</span></section>
          <section className="panel"><div className="panel-head"><div><span className="section-kicker">Steg 1</span><h2>Välj vilket underlag du importerar</h2></div></div><div className="kind-grid">{(Object.entries(DATA_KINDS) as [DataKind, typeof DATA_KINDS[DataKind]][]).map(([key, item]) => <button className={dataKind === key ? "selected" : ""} key={key} onClick={() => chooseKind(key)}><span>{item.label}</span><small>{item.description}</small></button>)}</div></section>
          <section className="panel"><div className="panel-head"><div><span className="section-kicker">Steg 2</span><h2>Ladda upp originalfil</h2></div><span className="file-types">PDF · XLSX · XLS · CSV</span></div><label className={`dropzone ${file ? "has-file" : ""}`}><input type="file" accept=".pdf,.xlsx,.xls,.csv" onChange={(event) => { setFile(event.target.files?.[0] ?? null); setPreview(null); setMessage(null); }}/><UploadCloud size={30}/>{file ? <><strong>{file.name}</strong><span>{number.format(file.size / 1024)} kB</span></> : <><strong>Välj eller släpp en fil här</strong><span>Originalfilen sparas privat för full spårbarhet. Max 20 MB.</span></>}</label><div className="actions"><button className="primary" disabled={!file || busy} onClick={analyse}>{busy ? "Analyserar…" : "Analysera fil"}</button></div></section>
          {preview && <section className="panel"><div className="panel-head"><div><span className="section-kicker">Steg 3</span><h2>Kontrollera kolumnmappningen</h2></div><span className="row-count">{preview.totalRows} rader hittades</span></div><div className="mapping-grid">{selectedDefinition.fields.map((field) => <label key={field.key}><span>{field.label}{field.required && <b>*</b>}</span><select value={mapping[field.key] ?? ""} onChange={(event) => setMapping((current) => ({ ...current, [field.key]: event.target.value }))}><option value="">Inte mappad</option>{preview.headers.map((header) => <option value={header} key={header}>{header}</option>)}</select></label>)}</div><div className="preview-table"><table><thead><tr>{preview.headers.slice(0,8).map((header) => <th key={header}>{header}</th>)}</tr></thead><tbody>{preview.rows.slice(0,6).map((row, index) => <tr key={index}>{preview.headers.slice(0,8).map((header) => <td key={header}>{row[header] || "–"}</td>)}</tr>)}</tbody></table></div><div className="import-confirm"><div><ShieldCheck size={19}/><p><strong>Fail-closed import</strong><span>Ogiltiga eller osäkert mappade rader påverkar inte nyckeltalen.</span></p></div><button className="primary" disabled={!requiredComplete || busy} onClick={importFile}>{busy ? "Importerar…" : "Importera och spara"}</button></div></section>}
          {message && <div className={`message ${message.type}`}>{message.type === "success" ? <CheckCircle2 size={18}/> : <AlertTriangle size={18}/>} {message.text}</div>}
        </>}
      </div>}

      {view === "definitions" && <div className="content definitions-grid">
        <section className="panel"><div className="panel-head"><div><span className="section-kicker">Beräkningsmodell</span><h2>Transportavdelningens sex nyckeltal</h2></div><BarChart3 size={20}/></div><div className="formula-list"><div><strong>Omsättning</strong><code>Σ verifierade intäktsrader</code></div><div><strong>Resultat</strong><code>Omsättning − övriga kostnader − diesel</code></div><div><strong>Intäkt per lastbil</strong><code>Omsättning / intäktsbärande lastbilar</code></div><div><strong>Beläggningsgrad fordon</strong><code>Belagda timmar / tillgängliga timmar</code></div><div><strong>Dieselkostnad</strong><code>Dieselkostnad / omsättning</code></div><div><strong>Debiteringsgrad chaufförer</strong><code>Debiterbara timmar / betalda timmar</code></div></div></section>
        <section className="panel architecture-panel"><div className="panel-head"><div><span className="section-kicker">API-förberedd</span><h2>Samma datakontrakt – ny transportväg</h2></div><Database size={20}/></div><div className="flow"><div><FileSpreadsheet size={20}/><span>PDF / Excel<strong>Manuell import nu</strong></span></div><ChevronRight/><div><Database size={20}/><span>KPI-datakontrakt<strong>Validerad data</strong></span></div><ChevronRight/><div><LayoutDashboard size={20}/><span>Humla KPI<strong>Samma beräkningar</strong></span></div></div><p>När respektive API aktiveras ersätter datamotorn filtransporten. KPI-appen fortsätter läsa samma normaliserade fält och behöver inte byggas om.</p></section>
        <section className="panel governance"><div><ShieldCheck size={20}/><span><strong>KPI äger reglerna</strong>Definitioner, mål och fördelningar ligger i KPI-appen.</span></div><div><Database size={20}/><span><strong>Datamotorn äger källdata</strong>API-inhämtning, identitet, provenance och dublettskydd hanteras bakom kulisserna.</span></div></section>
      </div>}
    </main>
  </div></div>;
}
