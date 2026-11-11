import 'server-only';
import {createClient} from '@/lib/supabase/server';
export async function orderAccess(){const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return null;const {data:m,error}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();if(error||!m)return null;const {data:ok}=await db.rpc('hub_has_permission',{p_tenant_id:m.tenant_id,p_permission:'kpi.manage'});return ok===true?{db,tenantId:m.tenant_id,userId:user.id}:null;}
