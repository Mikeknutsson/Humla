import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {PaymentForecastWorkspace} from '@/app/_components/payment-forecast-workspace';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import Link from 'next/link';
export const dynamic='force-dynamic';
export default async function Page(){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:m}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 const {data:allowed}=m?await db.rpc('hub_has_permission',{p_tenant_id:m.tenant_id,p_permission:'kpi.manage'}):{data:false};
 if(!allowed)return <main><h1>Du saknar behörighet till avdelningens betalningsprognos.</h1></main>;
 return <KpiDetailShell query="" title="Betalningsprognos" breadcrumb="Humla Dashboard / Ekonomi" extraNavigation={<><Link href="/kpi?view=monthly" prefetch={false}>Månadsrapport</Link><Link href="/kpi/kontrollpanel" prefetch={false}>Kontrollpanel</Link></>}><PaymentForecastWorkspace/></KpiDetailShell>;
}
