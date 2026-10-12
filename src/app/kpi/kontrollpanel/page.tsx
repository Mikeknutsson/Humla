import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {KpiControlWorkspace,type Section} from '@/app/_components/kpi-control-workspace';
export const dynamic='force-dynamic';
export default async function ControlPanel({searchParams}:{searchParams:Promise<{section?:string;from?:string;to?:string}>}){
 const {section,from,to}=await searchParams;
 const reviewPeriod=from&&to&&/^\d{4}-\d{2}-\d{2}$/.test(from)&&/^\d{4}-\d{2}-\d{2}$/.test(to)?{from,to}:undefined;
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return <main>Ingen aktiv arbetsyta. <a href="/kpi">Till Dashboard</a></main>;
 const [{data:rules,error},{data:registry}]=await Promise.all([db.rpc('hub_kpi_admin_rules_v1',{p_tenant_id:member.tenant_id}),db.rpc('hub_kpi_admin_unit_builder_v2',{p_tenant_id:member.tenant_id})]);
 if(error)return <main>KPI-administratör krävs för kontrollpanelen. <a href="/kpi">Till Dashboard</a></main>;
 return <KpiControlWorkspace rules={rules} candidates={registry?.candidates??[]} reviewPeriod={reviewPeriod} initialSection={(['identities','economic_review','matching','allocation','project_vehicle','units','project_group','cost','article','depreciation','review'].includes(section??'')?section:'matching') as Section}/>;
}
