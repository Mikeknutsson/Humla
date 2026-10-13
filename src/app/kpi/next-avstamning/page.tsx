import Link from 'next/link';
import { KpiDetailShell } from '@/app/_components/kpi-detail-shell';
import { reviewAccess, reviewPage } from '@/lib/hub/review-access';
export const dynamic = 'force-dynamic';
const labels: Record<string, string> = {
  all: 'Alla originalrader', current_scope: 'Befintligt rapporturval',
  candidate_include_unallocated: 'Komplettering väntar på verifiering', included_unallocated: 'Ingår – fordonsfördelning granskas',
  reexport: 'Återimporterat innehåll', ignored_zero: 'Nollrader',
  source_policy_review: 'Rapportpolicy eller dokument behöver granskas', account_rule_review: 'Kontoregel saknas',
  validation_review: 'Validering behöver granskas', invalid_economic: 'Ogiltigt belopp eller datum',
  withdrawn: 'Återtagen import', batch_review: 'Import behöver granskas',
};
type Report = {
  totalRows: number; selectedRows: number;
  activation: { active: boolean; rows: number; amount: string; difference: number | null } | null;
  totals: { state: string; currency: string; rows: number; amount: string }[];
  accounts: { account: string; description: string; currency: string; rows: number; amount: string }[];
  items: { row_id: string; canonical_row_id: string; state: string; occurred_on: string; project: string; account: string; amount: string; currency: string; row_number: number; file_name: string; source_data: Record<string, unknown> }[];
};
const money = (amount: string, currency: string) => `${new Intl.NumberFormat('sv-SE', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(amount))} ${currency}`;
export default async function NextCompleteness({ searchParams }: { searchParams: Promise<{ page?: string; state?: string }> }) {
  const access = await reviewAccess();
  if (!access) return <main className="content"><h1>Åtkomst saknas</h1></main>;
  const query = await searchParams, page = reviewPage(query.page);
  const state = Object.hasOwn(labels, query.state ?? '') ? query.state! : 'all';
  const { data, error } = await access.db.rpc('hub_next_completeness_review_v1', { p_tenant_id: access.tenantId, p_page: page, p_state: state });
  const report = error ? null : data as Report | null;
  return <KpiDetailShell query="" title="NEXT – kostnadsavstämning" breadcrumb="Humla Dashboard / Avstämning / NEXT" extraNavigation={<Link href="/kpi/avstamning" prefetch={false}>Avstämning & regler</Link>}>
    <div className="content">{!report ? <section className="panel"><p>Kostnadsavstämningen kunde inte hämtas. Saknat underlag visas inte som noll.</p></section> : <>
      <section className="panel"><h2>Komplettering av saknade kostnader</h2>
        {report.activation ? <>
          <p>{report.activation.active ? 'Kompletteringen är verifierad och aktiv i dashboarden.' : 'Kompletteringen väntar på verifierad publicering.'}</p>
          <p>{report.activation.rows} externa, kontomappade rader · {money(report.activation.amount, 'SEK')}.</p>
          {report.activation.active && report.activation.difference !== null && <p>Avstämningsdifferens för kompletteringen: {money(String(report.activation.difference), 'SEK')}.</p>}
        </> : <p>Ingen komplettering är publicerad.</p>}
        <p>Giltiga kostnader kan ingå i totalresultatet utan en säker fordonsfördelning. Dessa rader fördelas inte automatiskt på fordon. Konton utan regel, interna poster och rapportpolicy granskas separat.</p>
      </section>
      <section className="panel"><h2>Hela importhistoriken – {report.totalRows} rader</h2>
        <p>Beloppen nedan är ursprungsbelopp, inte en summering av KPI-kostnaden. Återtagna importer, återimporter och interna/schablonposter ska inte summeras till ett resultat. Bränsleavstämningen kan också ändra hur ett befintligt ursprungsbelopp representeras i KPI.</p>
        <table><thead><tr><th>Radstatus</th><th>Rader</th><th>Ursprungsbelopp</th></tr></thead><tbody>{report.totals.map(t => <tr key={t.state + t.currency}><td><Link href={`?state=${encodeURIComponent(t.state)}`} prefetch={false}>{labels[t.state] ?? t.state}</Link></td><td>{t.rows}</td><td>{money(t.amount, t.currency)}</td></tr>)}</tbody></table>
        <p><Link href="?state=all" prefetch={false}>Visa alla rader</Link></p>
      </section>
      <section className="panel"><h2>Konton som behöver beslut</h2><p>Ingen automatisk BAS-mappning används. Konton som till exempel avser tankinköp, intern handel eller investeringar behöver också en beslutad ekonomisk behandling.</p>
        <details><summary>{report.accounts.length} konton/valutor i granskningen</summary><table><thead><tr><th>Konto</th><th>Källans beskrivning</th><th>Rader</th><th>Ursprungsbelopp</th></tr></thead><tbody>{report.accounts.map(a => <tr key={a.account + a.currency}><td>{a.account}</td><td>{a.description}</td><td>{a.rows}</td><td>{money(a.amount, a.currency)}</td></tr>)}</tbody></table></details>
      </section>
      <section className="panel"><h2>{labels[state]} – sida {page + 1}</h2>
        <table><thead><tr><th>Datum / projekt</th><th>Konto / belopp</th><th>Status / original</th></tr></thead><tbody>{report.items.map(r => <tr key={r.row_id}>
          <td>{r.occurred_on ?? 'Datum saknas'}<br/>Projekt {r.project ?? 'saknas'}</td><td>{r.account}<br/>{money(r.amount, r.currency)}</td><td>{labels[r.state] ?? r.state}<details><summary>{r.file_name} · rad {r.row_number}</summary><p>Rad: {r.row_id}</p>{r.canonical_row_id !== r.row_id && <p>Motsvarande första förekomst: {r.canonical_row_id}</p>}<pre>{JSON.stringify(r.source_data, null, 2)}</pre></details></td>
        </tr>)}</tbody></table>
        <nav aria-label="Avstämningssidor">{page > 0 && <Link href={`?state=${encodeURIComponent(state)}&page=${page - 1}`}>Föregående sida</Link>} {' '}{(page + 1) * 100 < report.selectedRows && <Link href={`?state=${encodeURIComponent(state)}&page=${page + 1}`}>Nästa sida</Link>}</nav>
      </section>
    </>}</div>
  </KpiDetailShell>;
}
