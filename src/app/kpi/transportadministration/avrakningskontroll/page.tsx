import Link from "next/link";
import {redirect} from "next/navigation";
import {KpiDetailShell} from "@/app/_components/kpi-detail-shell";
import {settlementPath as base} from "@/app/_components/kpi-transport-administration-nav";
import {createClient} from "@/lib/supabase/server";
import {stenaPaymentDate} from "@/lib/hub/payment-evidence-model";
import MailAttachments from "./MailAttachments";
import ReviewEditor from "./ReviewEditor";
import type {RowReview} from "./review";

export const dynamic = "force-dynamic";

const importUrl = "/kpi?view=import&import_source=stena";
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
 const review = params.review === "1";

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

 const [summary, mail] = await Promise.all([
  db.rpc("hub_stena_settlement_workspace", {
   p_tenant: member.tenant_id, p_month: month + "-01", p_page: page, p_only_review: review,
  }),
  member.role === "owner" ? db.from("hub_gmail_attachments").select("id,filename,sender,subject,received_at")
   .eq("tenant_id", member.tenant_id).eq("status", "stored")
   .or("filename.ilike.%.pdf,filename.ilike.%.xlsx,filename.ilike.%.xls")
   .order("received_at", {ascending: false}).limit(100) : null,
 ]);
 const report = summary.data as Report | null;
 const pageUrl = (index: number) => base + "?" + new URLSearchParams({
  month, page: String(index), ...(review ? {review: "1"} : {}),
 });

 return <KpiDetailShell query="" title="Avräkningskontroll"
  breadcrumb="Humla Dashboard / Transportadministration" transportAdministration>
  <div className="content">
   <section className="overview-hero">
    <div><h2>Stena Recycling AB</h2><p>Beräknat betalningsdatum <strong>{stenaPaymentDate(month + "-01")}</strong> · Belopp exklusive moms</p></div>
    <Link href={importUrl} className="primary">Importera Stena-Excel</Link>
   </section>
   <section className="period-bar" aria-label="Leveransperiod">
    <form method="get" action={base} className="period-form">
     <label>Leveransmånad<input type="month" name="month" min="2000-01" max="2099-12" defaultValue={month} required/></label>
     <label>Visa bara rader att granska<input type="checkbox" name="review" value="1" defaultChecked={review}/></label>
     <button type="submit">Visa period</button>
    </form>
    <Link className="secondary" href="/kpi/betalningsprognos">Betalningsprognos</Link>
   </section>
   {summary.error && <p role="alert">Underlaget kunde inte hämtas. Försök igen.</p>}
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
   <h2>Bokningar och avvikelser</h2>
   {!!report.totals.fallback_rows && <p>{report.totals.fallback_rows} matchade på regnummer, transportdag och belopp.</p>}
   <p>Spara vad som behöver följas upp eller markera raden som granskad. Om beloppen eller matchningen ändras kommer raden tillbaka i granskningslistan.</p>
   {report.rows.length > 0 ? <div className="table-wrap"><table className="data-table">
    <thead><tr><th>Datum</th><th>Bokning / referens</th><th>Fordon</th><th>Workify</th><th>Historik</th><th>Avräknat</th><th>Avräknat minus Historik</th><th>Workify minus valt Stenabelopp</th><th>Kontrollresultat</th><th>Uppföljning</th></tr></thead>
    <tbody>{report.rows.map(row => <tr key={row.id}>
     <td>{row.date}</td><td>{row.booking || "–"}</td><td>{row.registration || "–"}</td>
     <td>{money(row.workify)}</td><td>{money(row.history)}{row.history_file && <><br/><small>{row.history_file}</small></>}</td>
     <td>{money(row.settled)}{row.settled_file && <><br/><small>{row.settled_file}</small></>}</td>
     <td>{money(row.settlement_difference)}</td><td>{money(row.workify_difference)}</td>
     <td>{statuses[row.status]}{row.match_method === "registration_date_amount" && <small>Matchad på regnr, dag och belopp</small>}</td>
     <td>{row.fingerprint && <ReviewEditor key={row.revision + row.fingerprint} row={row} month={month} page={page} review={review}/>}</td>
    </tr>)}</tbody>
   </table></div> : <p>Inga rader att visa för det här urvalet.</p>}
   <nav aria-label="Kontrollrader">
    {page > 0 && <Link href={pageUrl(page - 1)}>← Föregående</Link>}
    {(page + 1) * 80 < report.filtered_count && page < 1000 && <> <Link href={pageUrl(page + 1)}>Nästa →</Link></>}
   </nav>
  </section>}
  {mail && (mail.error ? <p role="alert">Mejlbilagorna kunde inte hämtas.</p> : <MailAttachments files={mail.data ?? []}/>)}
  <p><Link href="/integrationer/dokument-ovrigt/gmail">Öppna dokumentinkorgen</Link></p>
  </div>
 </KpiDetailShell>;
}
