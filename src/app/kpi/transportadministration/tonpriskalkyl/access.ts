import 'server-only';

import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';

export async function tonPriceAccess() {
  const db = await createClient();
  const {data:{user},error} = await db.auth.getUser();
  if (error || !user) redirect('/kpi/login');
  const member = await db.from('hub_tenant_members').select('tenant_id')
    .eq('user_id',user.id).eq('status','active').maybeSingle();
  if (member.error || !member.data) return null;
  const tenantId = member.data.tenant_id;
  const [permission,management] = await Promise.all([
    db.rpc('hub_can_use_ton_price',{p_tenant_id:tenantId}),
    db.rpc('hub_has_permission',{p_tenant_id:tenantId,p_permission:'kpi.manage'}),
  ]);
  if (permission.error || permission.data !== true) return null;
  return {db,tenantId,userId:user.id,canManage:management.data === true};
}
