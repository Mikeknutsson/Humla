import {redirect} from 'next/navigation';
import {GoogleMapsProvider} from '@/app/_components/google-maps-provider';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {readGoogleMapsConfig} from '@/lib/hub/google-maps-config';
import {stockholmDate} from '@/lib/hub/material-price-bank';
import {transportDocumentAccess} from '@/lib/hub/transport-document/access';
import {readTransportDocumentChoices} from '@/lib/hub/transport-document/choices';
import {DocumentWorkspace} from './workspace';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const access = await transportDocumentAccess();
  if (access.status === 'signed-out') redirect('/kpi/login');
  const [maps,choices] = access.status === 'ready'
    ? await Promise.all([readGoogleMapsConfig(access.db,access.tenantId),readTransportDocumentChoices(access)])
    : [null,null];

  return <KpiDetailShell title="Transportdokument" query="" breadcrumb="Humla Dashboard / Transportledning"
    transportAdministration={access.status === 'ready' ? 'transport-document' : false} personal={access.status !== 'ready'}>
    {access.status === 'ready' && choices ? <GoogleMapsProvider browserKey={maps?.browserKey ?? null}>
      <DocumentWorkspace {...choices} profileName={access.profileName} today={stockholmDate()}/>
    </GoogleMapsProvider> : <div className="content"><section className="panel"><p>Behörighet saknas för transportdokument.</p></section></div>}
  </KpiDetailShell>;
}
