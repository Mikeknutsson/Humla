import Link from 'next/link';
import { KpiDetailShell } from '@/app/_components/kpi-detail-shell';
import { reviewAccess } from '@/lib/hub/review-access';
import { loadCostRules } from '@/lib/hub/cost-rule-review';
import { getKpiReportStatus } from '@/lib/kpi/report-sync';

export const dynamic = 'force-dynamic';
type Review = {
  mode: string;
  approved: boolean;
  totals: { currency: string; review_state: string; rows: number; current_prepared_amount: string; allocation_review_rows: number }[];
  controls: { currency: string; partition_difference: string }[];
};
type NextStatus = { active: boolean; status: string; rows: number; amount: string; difference: number | null };
const labels: Record<string, string> = {
  candidate_include: 'Unika rader med godkänd orderstatus',
  candidate_duplicate: 'Dubblettrader', excluded_status: 'Annan orderstatus',
  ignored_zero: 'Nollrader', invalid: 'Ogiltigt datum eller belopp',
  review_required: 'Behöver granskas', excluded_withdrawn: 'Återtagen import',
  excluded_accounted_elsewhere: 'Bokförd i NEXT',
};
const money = (value: string, currency: string) => `${new Intl.NumberFormat('sv-SE', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value))} ${currency}`;
const list = (value: unknown) => Array.isArray(value) ? value.map(String).join(', ') : typeof value === 'string' ? value : '';

export default async function Reconciliation({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const access = await reviewAccess();
  if (!access) return <main className="content"><h1>Åtkomst saknas</h1><p>En aktiv arbetsyta med KPI-läsbehörighet krävs.</p></main>;
  const params = await searchParams;
  const query = new URLSearchParams();
  for (const key of ['fiscal_year', 'months', 'from', 'to', 'cost_center', 'group', 'unit', 'vehicle', 'project']) {
    if (typeof params[key] === 'string') query.set(key, params[key]);
  }
  const [status, revenue, rules, next] = await Promise.all([
    getKpiReportStatus(access.tenantId),
    access.db.rpc('hub_workify_review_v1', { p_tenant_id: access.tenantId, p_page: 0, p_state: 'all' }),
    loadCostRules(access.db, access.tenantId).then(data => ({ data, error: false })).catch(() => ({ data: [], error: true })),
    access.db.rpc('hub_next_reexport_status_v1', { p_tenant_id: access.tenantId }),
  ]);
  const report = revenue.error ? null : revenue.data as Review | null;
  const nextStatus = next.error ? null : next.data as NextStatus | null;
  return <KpiDetailShell query={query.toString()} title="Avstämning & regler" breadcrumb="Humla Dashboard / Avstämning">
    <div className="content">
      <section className="panel"><h2>KPI-underlag</h2>
        {status.error || !status.data ? <p>Rapportstatus kunde inte hämtas.</p> : <>
          <p>{status.data.status === 'ready' ? 'Dashboardens aktuella underlag är uppdaterat.' : status.data.generation ? 'Dashboarden visar senast publicerade underlag. En ny uppdatering är ännu inte klar.' : 'Inget publicerat KPI-underlag finns.'}</p>
          {status.data.synced_at && <p>Senast uppdaterat: {new Date(status.data.synced_at).toLocaleString('sv-SE', { timeZone: 'Europe/Stockholm' })}.</p>}
        </>}
        <p>Översikten följer valt verksamhetsår och period. Avstämningen nedan omfattar hela importhistoriken.</p>
        <Link href={`/kpi?${query}`} prefetch={false}>Visa översikten med samma urval →</Link>
      </section>
      <section className="panel"><h2>Workify-intäkter</h2>
        {!report ? <p>Avstämningen kunde inte hämtas.</p> : <>
          <p>{report.mode === 'active' ? 'Den godkända avstämningen är aktiv i KPI.' : report.approved ? 'Avstämningen är godkänd och väntar på verifierad publicering.' : 'Avstämningen är ett förslag och är ännu inte aktiv i KPI.'}</p>
          <p>Reported, ReadyForInvoicing och Invoiced ingår. Samma orderrad räknas en gång när orderstatusen ändras.</p>
          <table><thead><tr><th>Kontroll</th><th>Rader</th><th>Belopp i KPI</th><th>Fördelning behöver granskas</th></tr></thead><tbody>
            {report.totals.map(t => <tr key={t.review_state + t.currency}><td><Link href={`/intaktskontroll?state=${encodeURIComponent(t.review_state)}`} prefetch={false}>{labels[t.review_state] ?? t.review_state}</Link></td><td>{t.rows}</td><td>{money(t.current_prepared_amount, t.currency)}</td><td>{t.allocation_review_rows}</td></tr>)}
          </tbody></table>
          {report.controls.map(c => <p key={c.currency}>Kontrolldifferens vid uppdelning av KPI-beloppen: <strong>{money(c.partition_difference, c.currency)}</strong>.</p>)}
        </>}
        <Link href="/intaktskontroll" prefetch={false}>Visa orderrader och originalunderlag →</Link>
      </section>
      <section className="panel"><h2>NEXT – återimporterade kostnader</h2>
        {!nextStatus ? <p>Kontrollstatus kunde inte hämtas.</p> : <>
          <p>{nextStatus.active ? 'Korrigeringen är verifierad och aktiv i dashboarden.' : nextStatus.status === 'pending' ? 'Korrigeringen väntar på verifierad publicering.' : 'Ingen korrigering är publicerad.'}</p>
          <p>{nextStatus.rows} återimporterade rader · {money(nextStatus.amount, 'SEK')} {nextStatus.active ? 'undantas från KPI.' : 'i korrigeringsunderlaget.'}</p>
          {nextStatus.active && nextStatus.difference !== null && <p>Avstämningsdifferens för korrigeringen: {money(String(nextStatus.difference), 'SEK')}.</p>}
          <p>Originalraderna är kvar. Kontrollen gäller återimporter, inte en färdig avstämning av alla NEXT-kostnader.</p>
        </>}
        <Link href="/kostnadskontroll" prefetch={false}>Visa kostnadsrader och spårbarhet →</Link>
      </section>
      <section className="panel"><h2>Kostnadsfördelningsregler</h2>
        {rules.error ? <p>Reglerna kunde inte hämtas.</p> : <>
          <p>{rules.data.filter(r => r.enabled).length} aktiva och {rules.data.filter(r => !r.enabled).length} inaktiva regler. Tidigare projekt- och kontomappningar finns kvar i Kontrollpanelen.</p>
          <table><thead><tr><th>Regel / källa</th><th>Mottagare</th><th>Giltighet</th><th>Status</th></tr></thead><tbody>{rules.data.map(r => <tr key={r.id}>
            <td><strong>{r.name}</strong><br/>{list(r.source_scope.project_references) || list(r.source_scope.project_reference) || list(r.source_scope.source_unit_names)}</td>
            <td>{list(r.target_scope.recipient_unit_names) || list(r.target_scope.business_group) || (r.allocation_method === 'manual' ? 'Bekräftas på varje kostnadsrad' : 'Behöriga aktiva enheter')}<br/>{r.include_in_vehicle_result ? 'Fordonsresultat' : 'Övergripande resultat'}</td>
            <td>{r.valid_from ?? 'Start saknas'} – {r.valid_to ?? 'tills vidare'}</td><td>{r.enabled ? 'Aktiv' : 'Inväntar avstämning'}</td>
          </tr>)}</tbody></table>
          <p>Inaktiva regler påverkar ännu inte fordonsresultatet. Mottagarnas giltighetsperioder kontrolleras på kostnadsradens datum.</p>
        </>}
        <p><Link href="/kostnadskontroll" prefetch={false}>Visa kostnadsrader och regelunderlag →</Link></p>
        <p><Link href={`/kpi/kontrollpanel?${query}&section=allocation`} prefetch={false}>Öppna fördelning i Kontrollpanelen →</Link> · <Link href="/fordonshistorik" prefetch={false}>Historiskt fordonsunderlag</Link></p>
      </section>
    </div>
  </KpiDetailShell>;
}
