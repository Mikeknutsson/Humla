import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {StenaImport} from '@/app/_components/stena-import';
import Link from 'next/link';
export const dynamic='force-dynamic';
export default async function StenaPage(){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();
 const {data:allowed}=member?await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.manage'}):{data:false};
 if(!allowed)return <main className="content"><h1>Du saknar importbehörighet</h1></main>;
 return <main className="content"><Link href="/integrationer/projekt-order">← Projekt &amp; order</Link><h1>Stena – import</h1><StenaImport/></main>;
}
