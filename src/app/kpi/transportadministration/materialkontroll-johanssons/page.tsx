import {redirect} from 'next/navigation';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {createClient} from '@/lib/supabase/server';
import MaterialWorkspace from './workspace';

export const dynamic = 'force-dynamic';
const title = 'Materialkontroll Johanssons';

export default async function Page() {
  const db = await createClient();
  const {data: {user}} = await db.auth.getUser();
  if (!user) redirect('/kpi/login');
  const {data: member} = await db.from('hub_tenant_members').select('tenant_id,role')
    .eq('user_id', user.id).eq('status', 'active').maybeSingle();
  const {data: allowed} = member ? await db.rpc('hub_has_permission', {
    p_tenant_id: member.tenant_id, p_permission: 'kpi.manage',
  }) : {data: false};
  if (!member || !allowed) return <KpiDetailShell query="" title={title} breadcrumb="Humla Dashboard / Transportadministration" transportAdministration="material">
    <div className="content"><section className="panel"><p>KPI-administratör krävs för materialkontrollen.</p></section></div>
  </KpiDetailShell>;
  const mail = member.role === 'owner' ? await db.from('hub_gmail_attachments')
    .select('id,filename,sender,subject,received_at')
    .eq('tenant_id', member.tenant_id).eq('status', 'stored')
    .or('filename.ilike.%.xls,filename.ilike.%.xlsx')
    .order('received_at', {ascending: false}).order('id').limit(250) : null;
  const candidates = (mail?.data ?? []).map(file => ({
    ...file, likely: /johans+s?ons|kyll?inge|^elleholm\.xls/i.test(file.filename) ||
      /johans+s?ons|kyll?inge/i.test(`${file.sender} ${file.subject}`),
  }));
  const attachments = [...candidates.filter(file => file.likely), ...candidates.filter(file => !file.likely)];
  return <KpiDetailShell query="" title={title} breadcrumb="Humla Dashboard / Transportadministration" transportAdministration="material">
    <MaterialWorkspace attachments={attachments} mailAvailable={!!mail} mailError={!!mail?.error}/>
  </KpiDetailShell>;
}
