import 'server-only';

import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';

export async function googleHubAccess() {
  const db = await createClient();
  const {data:{user}, error} = await db.auth.getUser();
  if (error || !user) redirect('/kpi/login');
  const membership = await db.from('hub_tenant_members').select('tenant_id,role')
    .eq('user_id',user.id).eq('status','active').maybeSingle();
  if (membership.error || !membership.data) return null;
  return {db, tenantId:membership.data.tenant_id, isOwner:membership.data.role === 'owner'};
}
