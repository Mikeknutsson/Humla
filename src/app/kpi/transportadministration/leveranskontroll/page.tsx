import {redirect} from 'next/navigation';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {createClient} from '@/lib/supabase/server';
import DeliveryWorkspace, {type Delivery} from './workspace';

export const dynamic = 'force-dynamic';
const title = 'Leveranskontroll Sortergården';

export default async function Page() {
  const db = await createClient();
  const {data: {user}} = await db.auth.getUser();
  if (!user) redirect('/kpi/login');

  const {data: member} = await db.from('hub_tenant_members').select('tenant_id')
    .eq('user_id', user.id).eq('status', 'active').maybeSingle();
  const result = member ? await db.rpc('hub_sortergard_delivery_check', {p_tenant: member.tenant_id}) : null;
  const denied = !member || result?.error?.code === '42501';
  const rows: Delivery[] = Array.isArray(result?.data) ? result.data : [];
  return <KpiDetailShell query="" title={title} breadcrumb="Humla Dashboard / Transportadministration" transportAdministration="delivery-check">
    <div className="content">
      {denied
        ? <section className="panel"><p>KPI-administratör krävs för leveranskontrollen.</p></section>
        : result?.error
          ? <section className="panel"><p>Leveranskontrollen kunde inte läsas in. Uppdatera sidan och försök igen.</p></section>
          : <DeliveryWorkspace rows={rows}/>}
    </div>
  </KpiDetailShell>;
}
