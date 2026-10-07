import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {KpiControlWorkspace,type Section} from '@/app/_components/kpi-control-workspace';
export const dynamic='force-dynamic';
export default async function ControlPanel({searchParams}:{searchParams:Promise<{section?:string}>}){
 const {section}=await searchParams;
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return <main>Ingen aktiv arbetsyta. <a href="/kpi">Till Dashboard</a></main>;
 const [{data:rules,error},{data:registry}]=await Promise.all([db.rpc('hub_kpi_admin_rules_v1',{p_tenant_id:member.tenant_id}),db.rpc('hub_kpi_admin_unit_builder_v2',{p_tenant_id:member.tenant_id})]);
 if(error)return <main>KPI-administratör krävs för kontrollpanelen. <a href="/kpi">Till Dashboard</a></main>;
 return <KpiControlWorkspace rules={rules} candidates={registry?.candidates??[]} initialSection={(['matching','allocation','project_vehicle','units','project_group','cost','article','depreciation','review'].includes(section??'')?section:'matching') as Section}/>;
}
