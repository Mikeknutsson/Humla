import 'server-only';
import {createClient} from '@/lib/supabase/server';
export async function aiContext(){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return {error:'Logga in för att fråga Humla.',status:401} as const;
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return {error:'Aktiv arbetsyta saknas.',status:403} as const;
 const {data:allowed,error}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.read'});
 if(error||!allowed)return {error:'Du saknar åtkomst till underlagen.',status:403} as const;
 return {db,userId:user.id,tenantId:member.tenant_id};
}
