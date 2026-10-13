import Link from 'next/link';
import { reviewAccess, reviewPage } from '@/lib/hub/review-access';
export const dynamic = 'force-dynamic';
type DayReport = {
  firstDate: string; lastDate: string; totalRows: number; evidenceRows: number; reviewRows: number; sourceReports: number;
  items: { employee_id: string; person_object_id: string | null; person_name: string | null;
    work_date: string; vehicle_object_id: string | null; vehicle_name: string | null;
    reason: string; source_report_ids: string[] }[];
};
const reasons: Record<string,string> = {
  missing_canonical_person: 'Person saknar verifierad Humla-identitet', missing_canonical_vehicle: 'Fordon saknar verifierad Humla-identitet',
  multiple_vehicles_same_day: 'Flera fordon samma dag – granskning krävs', dated_time_report_evidence: 'Entydigt daterat tidrapportunderlag'
};
export default async function HistoricalVehicleReview({ searchParams }: { searchParams: Promise<{ page?: string }> }) {
  const access = await reviewAccess();
  if (!access) return <section className="card"><h1>Åtkomst saknas</h1><p>En entydig aktiv arbetsyta med KPI-läsbehörighet krävs.</p></section>;
  const page = reviewPage((await searchParams).page);
  const {data,error} = await access.db.rpc('hub_transpa_day_review_v1', {p_tenant_id:access.tenantId,p_page:page});
  if (error || !data) return <section className="card"><h1>Fordonskontroll</h1><p>Det historiska underlaget kunde inte hämtas.</p></section>;
  const report = data as DayReport;
  return <>
    <header className="topbar"><div><span className="eyebrow">HUMLA HUB · HISTORIK</span><h1>Historisk fordonskontroll</h1>
      <p>Daterade TransPA-tidrapporter från 1 september 2025, kopplade genom verifierade Humla-identiteter. Underlaget är stöd för granskning och bevisar inte i sig en viss ekonomisk transaktions fordonsfördelning.</p></div></header>
    <section className="card"><h2>Hela tillgängliga historiken</h2><p>{report.sourceReports} tidrapporter · {report.totalRows} persondagar · {report.evidenceRows} entydiga dagar · {report.reviewRows} dagar behöver granskas.</p>
      <p>Första tillgängliga dag: {report.firstDate ?? 'saknas'}. Senaste: {report.lastDate ?? 'saknas'}. Ingen koppling extrapoleras till andra datum. Resultaten påverkar ännu inte KPI.</p></section>
    <section className="section"><h2>Persondagar – sida {page+1}</h2>
      <table><thead><tr><th>Person</th><th>Datum</th><th>Fordon</th><th>Underlag</th></tr></thead><tbody>{report.items.map(r => <tr key={r.employee_id+r.work_date}>
        <td>{r.person_name ?? 'Ej fastställd'}<small>{r.person_object_id}</small></td><td>{r.work_date}</td><td>{r.vehicle_name ?? 'Ej fastställt'}<small>{r.vehicle_object_id}</small></td><td>{reasons[r.reason] ?? r.reason}<details><summary>Tidrapporter</summary><p>{r.source_report_ids.join(', ')}</p></details></td>
      </tr>)}</tbody></table>
      <nav aria-label="Sidor">{page>0 && <Link href={`?page=${page-1}`}>Föregående sida</Link>} {' '}{(page+1)*100<report.totalRows && <Link href={`?page=${page+1}`}>Nästa sida</Link>}</nav>
      <p><Link href="/kostnadskontroll">Till kostnadskontrollen</Link></p>
    </section>
  </>;
}
