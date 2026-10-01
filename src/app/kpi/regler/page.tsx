import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {DatedRuleManager} from '@/app/_components/dated-rule-manager';
export const dynamic='force-dynamic';
export default async function Rules(){const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');const {data:m}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();if(!m)return <main>Arbetsyta saknas.</main>;const {data,error}=await db.rpc('hub_kpi_admin_rules_v1',{p_tenant_id:m.tenant_id});if(error)return <main>KPI-administratör krävs. <a href="/kpi">Till KPI</a></main>;return <main className="content" style={{maxWidth:1200,margin:'auto'}}><a href="/kpi?view=units">← KPI-inställningar</a><h1>Hub-regler och giltighetsperioder</h1><DatedRuleManager data={data}/></main>}
