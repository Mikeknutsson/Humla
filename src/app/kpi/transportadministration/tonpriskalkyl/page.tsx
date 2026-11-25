import {GoogleMapsProvider} from '@/app/_components/google-maps-provider';
import {readGoogleMapsConfig} from '@/lib/hub/google-maps-config';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {tonPriceAccess} from './access';
import {readPriceBank} from '@/lib/hub/material-price-bank-server';
import {stockholmDate} from '@/lib/hub/material-price-bank';
import TonPriceWorkspace from './workspace';
import OfferArchive from './offer-archive';
import {readOffers} from '@/lib/hub/ton-price-offer-archive';
import {reviewPage} from '@/lib/hub/review-access';
import {readWorkifyMaterialPrices} from '@/lib/hub/workify-material-prices';

export const dynamic = 'force-dynamic';

export default async function Page({searchParams}: {searchParams: Promise<{offertSida?: string}>}) {
  const archivePage = reviewPage((await searchParams).offertSida);
  const access = await tonPriceAccess();
  const [bank,maps,offers,workifyPrices] = access
    ? await Promise.all([readPriceBank(access),readGoogleMapsConfig(access.db,access.tenantId),readOffers(access,archivePage),readWorkifyMaterialPrices(access)])
    : [null,null,null,null];
  return <KpiDetailShell query="" title="Tonpriskalkyl" breadcrumb="Humla Dashboard / Transportadministration" transportAdministration="ton-price">
    {access ? <GoogleMapsProvider browserKey={maps?.browserKey ?? null}><TonPriceWorkspace bank={bank} workifyPrices={workifyPrices ?? []} today={stockholmDate()} draftKey={`humla:tonpris:v1:${access.tenantId}:${access.userId}`}>
      <OfferArchive offers={offers} page={archivePage}/>
    </TonPriceWorkspace></GoogleMapsProvider>
      : <div className="content"><section className="panel"><p>KPI-administratör krävs för tonpriskalkylen.</p></section></div>}
  </KpiDetailShell>;
}
