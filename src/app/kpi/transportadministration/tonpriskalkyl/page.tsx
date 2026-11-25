import {GoogleMapsProvider} from '@/app/_components/google-maps-provider';
import {readGoogleMapsConfig} from '@/lib/hub/google-maps-config';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {tonPriceAccess} from './access';
import {readPriceBank} from '@/lib/hub/material-price-bank-server';
import {stockholmDate} from '@/lib/hub/material-price-bank';
import TonPriceWorkspace from './workspace';
import OfferArchive from './offer-archive';
import {readOffers, openOfferRevision} from '@/lib/hub/ton-price-offer-archive';
import {reviewPage} from '@/lib/hub/review-access';
import {readWorkifyMaterialPrices} from '@/lib/hub/workify-material-prices';

export const dynamic = 'force-dynamic';

export default async function Page({searchParams}: {searchParams: Promise<{offertSida?: string; komplettera?: string}>}) {
  const params = await searchParams;
  const archivePage = reviewPage(params.offertSida);
  const revisionId = typeof params.komplettera === 'string' ? params.komplettera : '';
  const access = await tonPriceAccess();
  const [bank,maps,offers,workifyPrices,revision] = access
    ? await Promise.all([readPriceBank(access,true),readGoogleMapsConfig(access.db,access.tenantId),readOffers(access,archivePage),readWorkifyMaterialPrices(access),
      revisionId ? openOfferRevision(access,revisionId).catch(() => null) : null])
    : [null,null,null,null,null];
  return <KpiDetailShell query="" title="Tonpriskalkyl" breadcrumb="Humla Dashboard / Transportadministration" transportAdministration={access?.canManage ? 'ton-price' : false}
    personal={!access?.canManage} personalLink={access && !access.canManage ? {href:'/kpi/mina-enheter',label:'Mina enheter'} : undefined}>
    {access ? <GoogleMapsProvider browserKey={maps?.browserKey ?? null}>
      {revisionId && !revision && <div className="content"><p role="alert">Offerten kunde inte öppnas. Välj den igen i offertarkivet.</p></div>}
      <TonPriceWorkspace key={revision?.id ?? 'new'} revision={revision ?? undefined}
        bank={bank} workifyPrices={revision?.calculation_snapshot?.mode === 'quick'
          ? revision.calculation_snapshot.workifyPrices : workifyPrices ?? []}
        today={stockholmDate()} draftKey={`humla:tonpris:v1:${access.tenantId}:${access.userId}${revision ? ':'+revision.id : ''}`}>
      <OfferArchive offers={offers} page={archivePage}/>
    </TonPriceWorkspace></GoogleMapsProvider>
      : <div className="content"><section className="panel"><p>Behörighet saknas för tonpriskalkylen.</p></section></div>}
  </KpiDetailShell>;
}
