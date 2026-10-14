import Link from 'next/link';
import { KpiDetailShell } from '@/app/_components/kpi-detail-shell';
import { reviewAccess } from '@/lib/hub/review-access';
export const dynamic = 'force-dynamic';
type Source = { kind: string; source_label: string; rows: number; amount: string; allocation_review_rows: number };
type Center = { code: string; name: string; revenue: string; cost: string; revenue_rows: number; cost_rows: number; sources: Source[] };
type ProjectReview = { available: boolean; rows: number; cost: number; revenue: number; projects: { source: string; kind: string; project: string | null; rows: number; amount: number; matches: number; project_name: string | null; cost_center: string | null; effective_date: string | null; reason: string }[] };
type PersonnelCoverage = { available: boolean; salary_resources: number; registered_transpa_people: number; centers: { code: string; name: string; sources: { source: string; category: string; basis: string; rows: number; amount: number }[] }[]; registered_personnel_projects: { object_id: string; name: string; project: string; current_center: string; effective_date: string | null }[] };
const personnelBasis: Record<string, string> = { actual_payroll_flag: 'Markerat som faktisk lön', estimated_payroll: 'Schablon från arbetstid', payroll_basis_missing: 'Lönegrund saknas', next_work_time_reference: 'NEXT-arbetstidspost – lön ej verifierad', mapped_personnel_expense: 'Kontomappad personalutgift – kan vara arbetskläder eller utbildning' };
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
  const projectResponse = invalid ? null : await access.db.rpc('hub_kpi_unclassified_projects_v1', { p_tenant_id: access.tenantId, p_from: from, p_to: to });
  const projectReview = projectResponse && !projectResponse.error ? projectResponse.data as ProjectReview | null : null;
  const personnelResponse = invalid ? null : await access.db.rpc('hub_kpi_personnel_coverage_v1', { p_tenant_id: access.tenantId, p_from: from, p_to: to });
  const personnel = personnelResponse && !personnelResponse.error ? personnelResponse.data as PersonnelCoverage | null : null;
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
        <section className="panel"><h2>Personalkostnader – kontroll av underlag</h2>
          {!personnel?.available ? <p>Personalkontrollen kunde inte hämtas.</p> : <>
            <p>{personnel.registered_transpa_people} personer finns i TransPA-registret. {personnel.salary_resources} löneexportunderlag överlappar perioden. Ett löneexportunderlag kan avse en större period och är inte i sig en avstämd lönekostnad.</p>
            <p>Schablon från arbetstid, NEXT-arbetstidsposter och övriga personalutgifter visas separat. Saknat löneunderlag ska inte tolkas som noll personalkostnad.</p>
            <table><thead><tr><th>Verksamhet</th><th>Källa</th><th>Underlagets betydelse</th><th>Rader</th><th>Belopp i KPI</th></tr></thead><tbody>{personnel.centers.flatMap(c => c.sources.length ? c.sources.map(s => <tr key={`${c.code}:${s.source}:${s.basis}:${s.category}`}><td>{c.name}</td><td>{s.source}</td><td>{personnelBasis[s.basis] ?? 'Behöver granskas'}</td><td>{s.rows}</td><td>{money(s.amount)}</td></tr>) : [<tr key={c.code}><td>{c.name}</td><td colSpan={4}>Inget publicerat personalunderlag i denna kontroll</td></tr>])}</tbody></table>
            {['20', '40'].map(code => <p key={code}><strong>{code === '20' ? 'Sortergården' : 'Verkstad'}:</strong> {personnel.centers.find(c => c.code === code)?.sources.some(s => s.source === 'TransPA') ? 'TransPA-kostnader finns i KPI; lönegrund och täckning behöver stämmas av.' : 'TransPA-kostnader saknas i KPI. Komplettera med tids- eller löneunderlag för rätt personal och period.'}</p>)}
            <h3>Projekt markerade som Personal i aktuellt projektregister</h3>
            <p>Listan är registerunderlag, inte verifierade anställningar eller en historisk personalfördelning. Personkoppling och giltighet behöver styrkas separat.</p>
            <table><thead><tr><th>Projekt</th><th>Namn i registret</th><th>Nuvarande kostnadsställe</th><th>Gäller från</th></tr></thead><tbody>{personnel.registered_personnel_projects.map(p => <tr key={p.object_id}><td>{p.project}</td><td>{p.name}</td><td>{p.current_center}</td><td>{p.effective_date ?? 'Saknas'}</td></tr>)}</tbody></table>
          </>}
        </section>
        {['30', '20', '40', 'unclassified'].map(code => report.centers.find(c => c.code === code)).filter((c): c is Center => Boolean(c)).map(c => <section className="panel" key={c.code}>
          <h2>{c.name}{c.code !== 'unclassified' && ` · ${c.code}`}</h2>
          {c.code === 'unclassified' && <p>De här beloppen tillhör hela verksamheten. De är inte fördelade mellan de tre områdena och ska inte läggas på ett område utan verifierat underlag.</p>}
          <p>Intäkter i nuvarande KPI: {c.revenue_rows ? money(c.revenue) : 'Inga klassificerade intäktsrader – behöver kontrolleras'}. Kostnader i nuvarande KPI: {c.cost_rows ? money(c.cost) : 'Inga klassificerade kostnadsrader – behöver kontrolleras'}.</p>
          <table><thead><tr><th>Underlag</th><th>Typ</th><th>Rader</th><th>Belopp</th><th>Fördelning behöver granskas</th></tr></thead><tbody>{c.sources.map(s => <tr key={s.kind + s.source_label}><td>{s.source_label}</td><td>{s.kind === 'cost' ? 'Kostnad' : 'Intäkt'}</td><td>{s.rows}</td><td>{money(s.amount)}</td><td>{s.allocation_review_rows}</td></tr>)}</tbody></table>
          {c.code !== 'unclassified' && <p><Link href={`/kpi?cost_center=${c.code}&from=${from}&to=${to}`} prefetch={false}>Öppna verksamhetens KPI →</Link></p>}
        </section>)}
        <section className="panel"><h2>Kvar att avstämma</h2>
          <h3>Oklassificerade poster per projekt</h3>
          {!projectReview?.available ? <p>Projektgranskningen kunde inte hämtas.</p> : <>
            <p>{projectReview.rows} publicerade rader. Intäkter {money(projectReview.revenue)} och kostnader {money(projectReview.cost)}. Projektregistrets nuvarande koppling visas som underlag för granskning. Den ändrar inte den historiska klassificeringen.</p>
            <div style={{ overflowX: 'auto' }}><table><thead><tr><th>Projekt</th><th>Källa</th><th>Typ</th><th>Rader</th><th>Belopp</th><th>Nuvarande kostnadsställe</th><th>Registret gäller från</th><th>Behöver granskas</th></tr></thead><tbody>{projectReview.projects.map(p => <tr key={`${p.source}:${p.kind}:${p.project ?? 'missing'}`}>
              <td>{p.project ?? 'Projektreferens saknas'}{p.matches === 1 && p.project_name && ` · ${p.project_name}`}</td><td>{p.source}</td><td>{p.kind === 'cost' ? 'Kostnad' : 'Intäkt'}</td><td>{p.rows}</td><td>{money(p.amount)}</td><td>{p.matches === 1 ? p.cost_center ?? 'Saknas' : 'Inte entydigt'}</td><td>{p.matches === 1 ? p.effective_date ?? 'Saknas' : '—'}</td><td>{p.reason === 'historical_date_review' ? 'Historisk giltighet' : p.reason === 'ambiguous_project_identity' ? 'Flera Humla-projekt' : p.reason === 'classification_review' ? 'Klassificeringen' : p.reason === 'missing_effective_date' ? 'Giltighetsdatum saknas' : p.reason === 'missing_cost_center' ? 'Kostnadsställe saknas' : 'Projektunderlag saknas'}</td>
            </tr>)}</tbody></table></div>
          </>}
          <p>Kostnader som inväntar kontoregel eller beslut om rapportpolicy ingår inte i dessa tabeller. Tankinköp ska stämmas av mot Piusi-förbrukning och personalkostnader mot TransPA innan nya belopp tas med.</p>
          <p><Link href="/kpi/next-avstamning" prefetch={false}>Kostnadsrader som behöver beslut →</Link> · <Link href="/intaktskontroll" prefetch={false}>Workify-order och originalrader →</Link></p>
        </section>
      </>)}
    </div>
  </KpiDetailShell>;
}
