import Link from "next/link";
import {redirect} from "next/navigation";
import {KpiDetailShell} from "@/app/_components/kpi-detail-shell";
import {settlementPath as base} from "@/app/_components/kpi-transport-administration-nav";
import {createClient} from "@/lib/supabase/server";
import {stenaPaymentDate} from "@/lib/hub/payment-evidence-model";
import MailAttachments from "./MailAttachments";
import ReviewEditor from "./ReviewEditor";
import {StenaImport} from "@/app/_components/stena-import";
import {reviewLabels} from "./review";
import styles from "./workspace.module.css";
import type {RowReview} from "./review";

export const dynamic = "force-dynamic";

const tabs = {queue:"Att granska", all:"Alla bokningar", imports:"Underlag & import"} as const;
type ImportFile = {entry_id:string;file_name:string;kind:string;status:string;imported_at:string;period_start:string|null;period_end:string|null;row_count:number;review_rows:number};
const dateTime = new Intl.DateTimeFormat("sv-SE",{dateStyle:"short",timeZone:"Europe/Stockholm"});
const amounts = new Intl.NumberFormat("sv-SE", {style: "currency", currency: "SEK"});
const money = (value: number | null) => value === null ? "–" : amounts.format(value);

const statuses = {
 difference: "Beloppsavvikelse",
 matched: "Avräknat",
 missing_amount: "Ofullständigt belopp",
 multiple_bookings: "Workify-rad gäller flera bokningar",
 open: "Inväntar avräkning",
 portal_only: "Saknar entydig Workify-match",
 workify_only: "Workify-rad utan entydig match",
};

type Comparison = RowReview & {
 id: string;
 booking: string;
 date: string;
 registration: string | null;
 workify: number | null;
 history: number | null;
 settled: number | null;
 history_file: string | null;
 settled_file: string | null;
 settlement_difference: number | null;
 workify_difference: number | null;
 status: keyof typeof statuses;
 match_method?: "booking" | "registration_date_amount" | null;
};

type Report = {
 report_available: boolean;
 totals: {rows: number; review_rows: number; reviewed_rows: number; fallback_rows?: number; workify: number | null; history: number | null; settled: number | null};
 rows: Comparison[];
 filtered_count: number;
};

export default async function Page({searchParams}: {searchParams: Promise<Record<string, string | string[] | undefined>>}) {
 const params = await searchParams;
 const currentMonth = new Intl.DateTimeFormat("sv-SE", {
  timeZone: "Europe/Stockholm", year: "numeric", month: "2-digit",
 }).format(new Date());
 const month = typeof params.month === "string" && /^20\d{2}-(0[1-9]|1[0-2])$/.test(params.month)
  ? params.month : currentMonth;
 const requestedPage = Number(typeof params.page === "string" ? params.page : "0");
 const page = Number.isInteger(requestedPage) && requestedPage >= 0 && requestedPage <= 1000 ? requestedPage : 0;
 const tab = params.tab === "all" || params.tab === "imports" ? params.tab : params.review === "0" ? "all" : "queue";
 const review = tab === "queue";
 const isImport = tab === "imports";

 const db = await createClient();
 const {data: {user}} = await db.auth.getUser();
 if (!user) redirect("/kpi/login");
 const {data: member} = await db.from("hub_tenant_members").select("tenant_id,role")
  .eq("user_id", user.id).eq("status", "active").maybeSingle();
 if (!member) return <section className="section"><h1>Avräkningskontroll</h1><p>Aktiv arbetsyta saknas.</p></section>;

 const {data: allowed, error: permissionError} = await db.rpc("hub_has_permission", {
  p_tenant_id: member.tenant_id, p_permission: "kpi.manage",
 });
 if (!allowed) return <section className="section"><h1>Avräkningskontroll</h1>
  <p>{permissionError ? "Behörigheten kunde inte kontrolleras." : "KPI-administratör krävs för avräkningskontrollen."}</p></section>;

 const [summary, imports, mail] = await Promise.all([
  isImport ? null : db.rpc("hub_stena_settlement_workspace", {
   p_tenant: member.tenant_id, p_month: month + "-01", p_page: page, p_only_review: review,
  }),
  isImport ? db.rpc("hub_kpi_import_history",{t:member.tenant_id,p_kind:"stena",p_page:0}) : null,
  isImport && member.role === "owner" ? db.from("hub_gmail_attachments").select("id,filename,sender,subject,received_at,document_id")
   .eq("tenant_id", member.tenant_id).eq("status", "stored")
   .or("filename.ilike.%.pdf,filename.ilike.%.xlsx,filename.ilike.%.xls")
   .order("received_at", {ascending: false}).order("id").limit(500) : null,
 ]);
 const report = summary?.data as Report | null;
 const importFiles = (imports?.data?.imports ?? []) as ImportFile[];
 const pageUrl = (index: number) => base + "?" + new URLSearchParams({
  month, page: String(index), tab,
 });

 return <KpiDetailShell query="" title="Avräkningskontroll"
  breadcrumb="Humla Dashboard / Transportadministration" transportAdministration>
  <div className="content">
   <section className="overview-hero">
    <div><h2>Stena Recycling AB</h2><p>Beräknat betalningsdatum <strong>{stenaPaymentDate(month + "-01")}</strong> · Belopp exklusive moms</p></div>
   </section>
   <nav className={styles.tabs} aria-label="Avräkningskontroll">
    {Object.entries(tabs).map(([key,label]) => <Link key={key} aria-current={tab===key?"page":undefined}
     className="secondary" href={base+"?"+new URLSearchParams({month,tab:key})}>{label}{key==="queue"&&report ? ` (${report.totals.review_rows})` : ""}</Link>)}
   </nav>
   {!isImport && <section className={`period-bar ${styles.filters}`} aria-label="Leveransperiod">
    <form method="get" action={base} className="period-form">
     <input type="hidden" name="tab" value={tab}/>
     <label>Leveransmånad<input type="month" name="month" min="2000-01" max="2099-12" defaultValue={month} required/></label>
     <button type="submit">Visa period</button>
    </form>
    <Link className="secondary" href="/kpi/betalningsprognos">Betalningsprognos</Link>
   </section>}
   {summary?.error && <p role="alert">Underlaget kunde inte hämtas. Försök igen.</p>}
   {report && <>
    {report.report_available ? <p>Workify följer den senast publicerade KPI-beräkningen. Nya Excelunderlag visas så snart de har importerats.</p> :
     <p>En publicerad KPI-beräkning behövs för att visa Workify-beloppen.</p>}
    <section className="metrics-grid" aria-label="Belopp och kontrollrader">
     <article className="metric-card"><span>Workify</span><strong>{money(report.totals.workify)}</strong></article>
     <article className="metric-card"><span>Stena Historik</span><strong>{money(report.totals.history)}</strong></article>
     <article className="metric-card"><span>Avräknat enligt Stena</span><strong>{money(report.totals.settled)}</strong></article>
     <article className="metric-card"><span>Att granska</span><strong>{report.totals.review_rows}</strong><small>{report.totals.reviewed_rows} granskade av {report.totals.rows} kontrollrader</small></article>
    </section>
   </>}
  {report && <section className="panel weekly-panel">
   <h2>{review ? "Öppna avvikelser" : "Alla bokningar"}</h2>
   {report.rows.length ? <div className={styles.rows}>{report.rows.map(row => <details key={row.id} className={styles.row}>
    <summary>
     <strong>{row.registration || "Regnummer saknas"}</strong><time dateTime={row.date}>{row.date}</time>
     <span>{row.booking || "Bokningsnummer saknas"}</span><span>{statuses[row.status]}</span>
     <span>{row.changed_since_review ? "Underlag ändrat" : row.revision>0 ? reviewLabels[row.review_state] : ""}</span>
     <strong className={styles.amount}>{row.workify_difference==null ? money(row.settled??row.history??row.workify) : `${money(row.workify_difference)} diff`}</strong>
    </summary>
    <div className={styles.details}>
     <dl className={styles.values}>
      <div><dt>Workify</dt><dd>{money(row.workify)}</dd></div>
      <div><dt>Stena Historik</dt><dd>{money(row.history)}{row.history_file&&<small>{row.history_file}</small>}</dd></div>
      <div><dt>Avräknat</dt><dd>{money(row.settled)}{row.settled_file&&<small>{row.settled_file}</small>}</dd></div>
      <div><dt>Avräknat minus Historik</dt><dd>{money(row.settlement_difference)}</dd></div>
      <div><dt>Workify minus valt Stenabelopp</dt><dd>{money(row.workify_difference)}</dd></div>
      {row.match_method&&<div><dt>Matchning</dt><dd>{row.match_method==="booking"?"Bokningsnummer":"Regnummer, dag och belopp"}</dd></div>}
     </dl>
     {row.fingerprint&&<ReviewEditor key={row.revision + row.fingerprint} row={row} month={month} page={page} review={review} embedded/>}
    </div>
   </details>)}</div> : <p>{report.filtered_count && page>0 ? "Sidan är tom. Gå till föregående sida." : review ? "Inga öppna avvikelser för perioden." : "Inga bokningar för perioden."}</p>}
   <nav className={styles.pagination} aria-label="Kontrollrader">
    {page > 0 && <Link className="secondary" href={pageUrl(page - 1)}>← Föregående</Link>}
    <span>{report.rows.length ? `${page*80+1}–${page*80+report.rows.length} av ${report.filtered_count}` : null}</span>
    {(page + 1) * 80 < report.filtered_count && page < 1000 && <Link className="secondary" href={pageUrl(page + 1)}>Nästa →</Link>}
   </nav>
  </section>}
  {isImport && <>
   <StenaImport refreshOnImport/>
   <section className="panel weekly-panel">
    <h2>Importerade Stena-filer</h2>
    {imports?.error ? <p role="alert">Importhistoriken kunde inte hämtas.</p> : !importFiles.length ? <p>Inga Stena-filer har importerats.</p> :
    <div className="table-wrap"><table className="data-table">
     <thead><tr><th>Fil</th><th>Importtyp</th><th>Importerad</th><th>Transportdatum</th><th>Rader</th><th>Kontroll</th></tr></thead>
     <tbody>{importFiles.map(file=><tr key={file.entry_id}>
      <td>{file.file_name}</td><td>{file.kind==="stena_settled"?"Avräknade transporter":"Historik"}</td>
      <td>{dateTime.format(new Date(file.imported_at))}</td><td>{file.period_start ?? "–"} – {file.period_end ?? "–"}</td><td>{file.row_count}</td>
      <td>{file.status==="incomplete"?"Ofullständig":file.kind==="stena_history"&&/^avräknade/i.test(file.file_name)?"Kontrollera importtyp":file.review_rows ? `${file.review_rows} saknar belopp` : "Klar"}</td>
     </tr>)}</tbody>
    </table></div>}
    <Link className="secondary" href="/kpi/importhistorik">Öppna fullständig importhistorik</Link>
   </section>
   {mail && (mail.error ? <p role="alert">Mejlbilagorna kunde inte hämtas.</p> : <MailAttachments files={mail.data ?? []}/>)}
   <p><Link href="/integrationer/dokument-ovrigt/gmail">Öppna dokumentinkorgen</Link></p>
  </>}
  </div>
 </KpiDetailShell>;
}
