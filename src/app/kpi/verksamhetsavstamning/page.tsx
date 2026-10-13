import Link from 'next/link';
import { KpiDetailShell } from '@/app/_components/kpi-detail-shell';
import { reviewAccess } from '@/lib/hub/review-access';
export const dynamic = 'force-dynamic';
type Source = { kind: string; source_label: string; rows: number; amount: string; allocation_review_rows: number };
type Center = { code: string; name: string; revenue: string; cost: string; revenue_rows: number; cost_rows: number; sources: Source[] };
type Report = { available: boolean; from: string; to: string; synced_at: string; centers: Center[]; active_allocation_rules: number; identity_correction: { status: string; result: { rows: number; amountDifference: number } } | null; fuel_correction?: { status: string; periodRows: number; periodAmount: number } | null; transpa_coverage?: { reports: number; employees: number; hours: number; cost_codes: { code: string; reports: number }[] } };
const money = (value: string | number) => `${new Intl.NumberFormat('sv-SE', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value))} kr`;
function validDate(value?: string) {
  return value && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value ? value : null;
}
export default async function CenterReconciliation({ searchParams }: { searchParams: Promise<{ from?: string; to?: string }> }) {
  const access = await reviewAccess();
  if (!access) return <main className="content"><h1>Åtkomst saknas</h1></main>;
  const params = await searchParams, now = new Date();
  const fiscalYear = now.getUTCFullYear() - (now.getUTCMonth() < 8 ? 1 : 0);
  const defaultFrom = `${fiscalYear}-09-01`;
  const defaultTo = `${fiscalYear + 1}-08-31`;
  const from = validDate(params.from) ?? defaultFrom, to = validDate(params.to) ?? defaultTo;
  const invalid = to < from || (Date.parse(to) - Date.parse(from)) / 86400000 > 366;
  const response = invalid ? null : await access.db.rpc('hub_kpi_center_reconciliation_v1', { p_tenant_id: access.tenantId, p_from: from, p_to: to });
  const report = response && !response.error ? response.data as Report | null : null;
  return <KpiDetailShell query="" title="Transport, Sortergården & Verkstad" breadcrumb="Humla Dashboard / Verksamhetsavstämning" extraNavigation={<Link href="/kpi/avstamning" prefetch={false}>Avstämning & regler</Link>}>
    <div className="content">
      <section className="panel"><h2>Avstämning per verksamhet</h2>
        <form method="get"><label>Från <input type="date" name="from" defaultValue={from} required /></label> <label>Till <input type="date" name="to" defaultValue={to} required /></label> <button type="submit">Visa perioden</button></form>
        <p>Transport 30 · Sortergården 20 · Verkstad 40. Standardurvalet är hela verksamhetsåret, september–augusti.</p>
        <p>Tabellerna visar det publicerade KPI-underlaget. Bokförda NEXT-intäkter och Workify-order visas separat eftersom eventuell överlappning mellan dem ännu behöver avstämmas. Beloppen är därför inte ett slutligt verifierat verksamhetsresultat.</p>
        {invalid && <p role="alert">Välj en giltig period på högst 367 kalenderdagar.</p>}
      </section>
      {!invalid && (!report?.available ? <section className="panel"><p>Avstämningen kunde inte hämtas. Saknat underlag visas inte som noll.</p></section> : <>
        <section className="panel"><h2>Kontrollstatus</h2>
          <p>Underlaget uppdaterat {new Date(report.synced_at).toLocaleString('sv-SE', { timeZone: 'Europe/Stockholm' })}.</p>
          <p>{report.identity_correction?.status === 'verified' ? `NEXT-intäkternas källkoppling är verifierad för ${report.identity_correction.result.rows} rader. Beloppsdifferens: ${money(report.identity_correction.result.amountDifference)}.` : 'Rättningen av NEXT-intäkternas källkoppling väntar på verifierad publicering.'}</p>
          {report.fuel_correction && <p>{report.fuel_correction.status === 'verified' ? `${report.fuel_correction.periodRows} NEXT-rader med originaltext exakt ”PS Olje AB” har kvar sitt originalunderlag men undantas som dubbel kostnad mot Piusi. Minskad KPI-kostnad i vald period: ${money(report.fuel_correction.periodAmount)}.` : 'Kontrollen av dubbelräknat bränsle väntar på verifierad publicering.'}</p>}
          <p>Levfakt PS Olje AB, Circle K och andra externa tankningar behålls separat. Egen-tank-rader undantas endast under månader där godtagna Piusi-kostnader faktiskt ingår.</p>
          <p>{report.active_allocation_rules} aktiva nya kostnadsfördelningsregler.</p>
        </section>
        {report.transpa_coverage && <section className="panel"><h2>Importerad TransPA-tid – täckning</h2>
          <p>{report.transpa_coverage.reports} tidsrapporter · {report.transpa_coverage.employees} personer · {new Intl.NumberFormat('sv-SE', { maximumFractionDigits: 2 }).format(report.transpa_coverage.hours)} timmar i vald period.</p>
          <p>Detta är aktuellt importerat tidsunderlag, inte lönebelopp eller en ny fördelning i KPI. En rapport kan ha flera kostnadskoder.</p>
          <table><thead><tr><th>Kostnadskod i TransPA</th><th>Tidsrapporter</th></tr></thead><tbody>{report.transpa_coverage.cost_codes.map(c => <tr key={c.code}><td>{c.code}</td><td>{c.reports}</td></tr>)}</tbody></table>
          {['20', '40'].filter(code => !report.transpa_coverage!.cost_codes.some(c => c.code === code)).map(code => <p key={code}><strong>{code === '20' ? 'Sortergården' : 'Verkstad'}:</strong> Inga importerade TransPA-tidsrapporter är märkta med kostnadskod {code} i perioden. Det betyder inte att verksamheten saknar personalkostnad. Tidsunderlag och kopplingar behöver kontrolleras.</p>)}
        </section>}
        {['30', '20', '40', 'unclassified'].map(code => report.centers.find(c => c.code === code)).filter((c): c is Center => Boolean(c)).map(c => <section className="panel" key={c.code}>
          <h2>{c.name}{c.code !== 'unclassified' && ` · ${c.code}`}</h2>
          {c.code === 'unclassified' && <p>De här beloppen tillhör hela verksamheten. De är inte fördelade mellan de tre områdena och ska inte läggas på ett område utan verifierat underlag.</p>}
          <p>Intäkter i nuvarande KPI: {c.revenue_rows ? money(c.revenue) : 'Inga klassificerade intäktsrader – behöver kontrolleras'}. Kostnader i nuvarande KPI: {c.cost_rows ? money(c.cost) : 'Inga klassificerade kostnadsrader – behöver kontrolleras'}.</p>
          <table><thead><tr><th>Underlag</th><th>Typ</th><th>Rader</th><th>Belopp</th><th>Fördelning behöver granskas</th></tr></thead><tbody>{c.sources.map(s => <tr key={s.kind + s.source_label}><td>{s.source_label}</td><td>{s.kind === 'cost' ? 'Kostnad' : 'Intäkt'}</td><td>{s.rows}</td><td>{money(s.amount)}</td><td>{s.allocation_review_rows}</td></tr>)}</tbody></table>
          {c.code !== 'unclassified' && <p><Link href={`/kpi?cost_center=${c.code}&from=${from}&to=${to}`} prefetch={false}>Öppna verksamhetens KPI →</Link></p>}
        </section>)}
        <section className="panel"><h2>Kvar att avstämma</h2>
          <p>Kostnader som inväntar kontoregel eller beslut om rapportpolicy ingår inte i dessa tabeller. Tankinköp ska stämmas av mot Piusi-förbrukning och personalkostnader mot TransPA innan nya belopp tas med.</p>
          <p><Link href="/kpi/next-avstamning" prefetch={false}>Kostnadsrader som behöver beslut →</Link> · <Link href="/intaktskontroll" prefetch={false}>Workify-order och originalrader →</Link></p>
        </section>
      </>)}
    </div>
  </KpiDetailShell>;
}
