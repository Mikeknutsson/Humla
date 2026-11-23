import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {tonPriceAccess} from './actions';
import TonPriceWorkspace from './workspace';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const access = await tonPriceAccess();
  return <KpiDetailShell query="" title="Tonpriskalkyl" breadcrumb="Humla Dashboard / Transportadministration" transportAdministration="ton-price">
    {access ? <TonPriceWorkspace draftKey={`humla:tonpris:v1:${access.tenantId}:${access.userId}`}/>
      : <div className="content"><section className="panel"><p>KPI-administratör krävs för tonpriskalkylen.</p></section></div>}
  </KpiDetailShell>;
}
