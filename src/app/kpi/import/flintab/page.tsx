import Link from 'next/link';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {yardAccess} from '@/lib/hub/sortergard-server';
import FlintabUpload,{type ImportHistory} from './upload';

export const dynamic='force-dynamic';

export default async function Page() {
  const access = await yardAccess();
  const history = access ? await access.db.rpc('hub_flintab_history',{p_tenant:access.tenantId}) : null;
  return <KpiDetailShell query="" title="Import – Flintab Fordonsvåg" breadcrumb="Humla Dashboard / Import"
    extraNavigation={<Link href="/kpi/sortergarden/arsrapport">Årsrapport Miljöförbundet</Link>}>
    <div className="content">{access ? <FlintabUpload history={history?.error ? null : history?.data as ImportHistory[]} />
      : <section className="panel">KPI-administratör krävs för Flintabimport.</section>}</div>
  </KpiDetailShell>;
}
