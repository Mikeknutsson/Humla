import Link from 'next/link';
import { reviewAccess, reviewPage } from '@/lib/hub/review-access';
export const dynamic = 'force-dynamic';
type CostReview = {
  totalRows: number; verifiedUniqueRows: number; verifiedDuplicateRows: number; possibleDuplicateRows: number;
  reviewRows: number; invalidRows: number; activeRules: number; inactiveRules: number;
  batchTotals: { currency: string; batch_status: string; rows: number; amount: string }[];
  items: { row_id: string; batch_id: string; row_number: number; occurred_on: string; project: string;
    amount: string; currency: string; batch_status: string; reason: string; candidate_row_id: string | null;
    file_name: string; source_data: Record<string, unknown>; validation_errors: unknown }[];
};
const reasons: Record<string,string> = {
  possible_duplicate_without_source_line_id: 'Möjlig dubblett – källrad-ID saknas',
  batch_and_source_identity_need_review: 'Import och radidentitet behöver granskas',
  missing_verified_source_line_id: 'Verifierad radidentitet saknas', invalid_economic_data: 'Ogiltigt belopp eller datum'
};
export default async function CostReviewPage({ searchParams }: { searchParams: Promise<{ page?: string }> }) {
  const access = await reviewAccess();
  if (!access) return <section className="card"><h1>Åtkomst saknas</h1><p>En entydig aktiv arbetsyta med KPI-läsbehörighet krävs.</p></section>;
  const page = reviewPage((await searchParams).page);
  const { data, error } = await access.db.rpc('hub_cost_review_v1', { p_tenant_id: access.tenantId, p_page: page });
  if (error || !data) return <section className="card"><h1>Kostnadskontroll</h1><p>Avstämningen kunde inte hämtas. Inga ekonomiska data har ändrats.</p></section>;
  const report = data as CostReview;
  const money = (amount: string, currency: string) => `${new Intl.NumberFormat('sv-SE', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(amount))} ${currency}`;
  return <>
    <header className="topbar"><div><span className="eyebrow">HUMLA HUB · GRANSKNING</span><h1>Kostnadskontroll</h1>
      <p>Samtliga kostnadsrader i arbetsytans importhistorik. Summorna är råa importbelopp och kan innehålla dubbletter.</p></div></header>
    <section className="stats">
      <article className="card"><b>{report.totalRows}</b><strong>Ursprungsrader</strong></article>
      <article className="card"><b>{report.verifiedUniqueRows}</b><strong>Verifierade unika</strong></article>
      <article className="card"><b>{report.verifiedDuplicateRows}</b><strong>Verifierade dubbletter</strong></article>
      <article className="card"><b>{report.reviewRows}</b><strong>Behöver granskas</strong><small>Varav {report.possibleDuplicateRows} möjliga dubbletter</small></article>
    </section>
    <section className="card"><h2>Avstämning före aktivering</h2>
      <p>{report.activeRules} aktiva och {report.inactiveRules} inaktiva fördelningsregler. {report.invalidRows} rader har ogiltigt belopp eller datum.</p>
      <p>Ekonomisk avstämningsdifferens: ännu inte fastställd. Inget belopp tas bort eller fördelas från denna vy. Ett verifikationsnummer och identiskt innehåll bevisar inte ensamma att två rader är samma transaktion.</p>
      <table><thead><tr><th>Importstatus</th><th>Rader</th><th>Råbelopp</th></tr></thead><tbody>{report.batchTotals.map(t => <tr key={t.batch_status+t.currency}><td>{t.batch_status}</td><td>{t.rows}</td><td>{money(t.amount,t.currency)}</td></tr>)}</tbody></table>
    </section>
    <section className="section"><h2>Radgranskning</h2><p>Sida {page+1}. 100 rader per sida; totalsummorna omfattar hela historiken.</p>
      <table><thead><tr><th>Projekt / datum</th><th>Källa</th><th>Belopp</th><th>Kontroll</th></tr></thead><tbody>
        {report.items.map(r => <tr key={r.row_id}><td>{r.project}<br/>{r.occurred_on}</td><td>{r.file_name}<br/>Rad {r.row_number} · {r.batch_status}</td><td>{money(r.amount,r.currency)}</td><td>{reasons[r.reason] ?? r.reason}
          <details><summary>Original och spårbarhet</summary><p>Rad: {r.row_id}<br/>Import: {r.batch_id}</p>{r.candidate_row_id && <p>Möjlig motsvarande rad: {r.candidate_row_id}</p>}<pre>{JSON.stringify(r.source_data,null,2)}</pre><p>Importkontroller: {JSON.stringify(r.validation_errors)}</p></details>
        </td></tr>)}
      </tbody></table>
      <nav aria-label="Sidor">{page>0 && <Link href={`?page=${page-1}`}>Föregående sida</Link>} {' '}{(page+1)*100<report.totalRows && <Link href={`?page=${page+1}`}>Nästa sida</Link>}</nav>
      <p><Link href="/intaktskontroll">Granska Workify-intäkter mot KPI</Link> · <Link href="/fordonshistorik">Granska daterat fordonsunderlag</Link></p>
    </section>
  </>;
}
