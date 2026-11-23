import {GoogleMapsProvider} from '@/app/_components/google-maps-provider';
import {readGoogleMapsConfig} from '@/lib/hub/google-maps-config';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {tonPriceAccess} from './access';
import {readPriceBank} from '@/lib/hub/material-price-bank-server';
import {stockholmDate} from '@/lib/hub/material-price-bank';
import TonPriceWorkspace from './workspace';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const access = await tonPriceAccess();
  const [bank, maps] = access ? await Promise.all([readPriceBank(access), readGoogleMapsConfig(access.db,access.tenantId)]) : [null,null];
  return <KpiDetailShell query="" title="Tonpriskalkyl" breadcrumb="Humla Dashboard / Transportadministration" transportAdministration="ton-price">
    {access ? <GoogleMapsProvider browserKey={maps?.browserKey ?? null}><TonPriceWorkspace bank={bank} today={stockholmDate()} draftKey={`humla:tonpris:v1:${access.tenantId}:${access.userId}`}/></GoogleMapsProvider>
      : <div className="content"><section className="panel"><p>KPI-administratör krävs för tonpriskalkylen.</p></section></div>}
  </KpiDetailShell>;
}
