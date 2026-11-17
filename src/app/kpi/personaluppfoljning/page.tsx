import Link from 'next/link';
import {reviewAccess} from '@/lib/hub/review-access';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
export const dynamic='force-dynamic';
export default async function PersonnelFollowup(){
 const access=await reviewAccess();
 if(!access)return <main className="content"><h1>Du saknar åtkomst till personaluppföljningen.</h1></main>;
 return <KpiDetailShell title="Personaluppföljning" breadcrumb="Humla Dashboard / Resurser / Anställda" query="cost_center=10">
  <section className="panel"><p><Link href="/kpi/resursuppfoljning">← Resursuppföljning</Link></p><h2>Uppföljning per anställd</h2><p>Varje anställd ska kunna följas oberoende av vilken maskin, vilket fordon eller vilket projekt personen arbetat på.</p></section>
  <section className="panel"><h2>Nyckeltal</h2><div className="table-wrap"><table className="data-table"><thead><tr><th>Arbetad tid</th><th>Registrerad resurstid</th><th>Debiterbar tid</th><th>Upparbetat värde</th><th>Personalkostnad</th></tr></thead><tbody><tr><td colSpan={5}>Underlag för personkopplade NeXT-rader och TransPA behöver verifieras innan nyckeltalen kan beräknas.</td></tr></tbody></table></div></section>
  <section className="panel"><h2>Dataprinciper</h2><p>En anställd identifieras med en stabil personnyckel. Maskin, fordon, projekt och arbetsorder är separata kopplingar till samma tidsrad. Arbetsinsatsen räknas en gång i ekonomiuppföljningen, även om den visas i båda dimensionerna.</p><p>Personuppgifter och kostnader ska endast visas för behöriga användare.</p></section>
 </KpiDetailShell>;
}