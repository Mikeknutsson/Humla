import Link from "next/link";
import {createClient} from "@/lib/supabase/server";
import {stenaPaymentDate} from "@/lib/hub/payment-evidence-model";
import MailAttachments from "./MailAttachments";

export const dynamic = "force-dynamic";

const base = "/integrationer/projekt-order/avrakningskontroll";
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

type Comparison = {
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
};

type Report = {
 report_available: boolean;
 totals: {rows: number; review_rows: number; workify: number | null; history: number | null; settled: number | null};
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
 if (!user) return <section className="section"><h1>Avräkningskontroll</h1><Link href="/kpi/login">Logga in i Humla</Link></section>;
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

 return <>
  <Link href="/integrationer/projekt-order" className="backlink">← Projekt & order</Link>
  <header className="topbar">
   <div><h1>Avräkningskontroll</h1><p>Stena Recycling AB</p></div>
   <Link href={importUrl} className="button">Importera måndagens Excel</Link>
  </header>
  <section className="panel">
   <form method="get" action={base} className="form-grid">
    <label>Leveransmånad<input type="month" name="month" min="2000-01" max="2099-12" defaultValue={month} required/></label>
    <label><input type="checkbox" name="review" value="1" defaultChecked={review}/> Visa bara rader att granska</label>
    <button type="submit">Visa period</button>
   </form>
   <p>Beräknat betalningsdatum <strong>{stenaPaymentDate(month + "-01")}</strong>. Beloppen är exklusive moms. <Link href="/kpi/betalningsprognos">Öppna betalningsprognosen</Link></p>
   {summary.error && <p role="alert">Underlaget kunde inte hämtas. Försök igen.</p>}
   {report && <>
    {report.report_available ? <p>Workify följer den senast publicerade KPI-beräkningen. Nya Excelunderlag visas så snart de har importerats.</p> :
     <p>En publicerad KPI-beräkning behövs för att visa Workify-beloppen.</p>}
    <dl className="linkgrid three">
     <div><dt>Workify</dt><dd>{money(report.totals.workify)}</dd></div>
     <div><dt>Stena Historik</dt><dd>{money(report.totals.history)}</dd></div>
     <div><dt>Avräknat enligt Stena</dt><dd>{money(report.totals.settled)}</dd></div>
    </dl>
    <p>{report.totals.rows} kontrollrader · {report.totals.review_rows} att granska</p>
   </>}
  </section>
  {report && <section className="panel">
   <h2>Bokningar och avvikelser</h2>
   {report.rows.length > 0 ? <div className="table-wrap"><table className="data-table">
    <thead><tr><th>Datum</th><th>Bokning / referens</th><th>Fordon</th><th>Workify</th><th>Historik</th><th>Avräknat</th><th>Avräknat minus Historik</th><th>Workify minus valt Stenabelopp</th><th>Status</th></tr></thead>
    <tbody>{report.rows.map(row => <tr key={row.id}>
     <td>{row.date}</td><td>{row.booking || "–"}</td><td>{row.registration || "–"}</td>
     <td>{money(row.workify)}</td><td>{money(row.history)}{row.history_file && <><br/><small>{row.history_file}</small></>}</td>
     <td>{money(row.settled)}{row.settled_file && <><br/><small>{row.settled_file}</small></>}</td>
     <td>{money(row.settlement_difference)}</td><td>{money(row.workify_difference)}</td>
     <td>{statuses[row.status]}</td>
    </tr>)}</tbody>
   </table></div> : <p>Inga rader att visa för det här urvalet.</p>}
   <nav aria-label="Kontrollrader">
    {page > 0 && <Link href={pageUrl(page - 1)}>← Föregående</Link>}
    {(page + 1) * 80 < report.filtered_count && page < 1000 && <> <Link href={pageUrl(page + 1)}>Nästa →</Link></>}
   </nav>
  </section>}
  {mail && (mail.error ? <p role="alert">Mejlbilagorna kunde inte hämtas.</p> : <MailAttachments files={mail.data ?? []}/>)}
  <p><Link href="/integrationer/dokument-ovrigt/gmail">Öppna dokumentinkorgen</Link></p>
 </>;
}
