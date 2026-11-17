import Link from 'next/link';
import {reviewAccess} from '@/lib/hub/review-access';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
export const dynamic='force-dynamic';
export default async function ResourceDimensions(){
 const access=await reviewAccess();
 if(!access)return <main className="content"><h1>Du saknar åtkomst till resursuppföljningen.</h1></main>;
 return <KpiDetailShell title="Resursuppföljning" breadcrumb="Humla Dashboard / Resurser" query="cost_center=10">
  <section className="panel"><h2>Två dimensioner – samma grunddata</h2><p>Maskiner och anställda följs upp separat. En registrerad arbetsinsats får kopplas till båda dimensionerna, men dess ekonomiska belopp får inte summeras två gånger i totalresultatet.</p></section>
  <section className="panel"><h2>1. Maskiner</h2><p>Registrerad tid, debiterade timmar, upparbetat värde, projekt och arbetsorder. Kostnader kopplas på per maskin när underlaget är verifierat.</p><p><Link href="/kpi/maskiner">Öppna maskinuppföljning →</Link></p></section>
  <section className="panel"><h2>2. Anställda</h2><p>Följ arbetad tid, resursfördelning och upparbetat värde per person, oberoende av maskin och fordon. Personalkostnad och debiteringsgrad visas först när underlaget är matchat.</p><p><Link href="/kpi/personaluppfoljning">Öppna personaluppföljning →</Link></p></section>
 </KpiDetailShell>;
}