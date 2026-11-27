import 'server-only';
import {createClient} from '@/lib/supabase/server';

export async function transportDocumentAccess() {
  const db = await createClient();
  const {data:{user},error} = await db.auth.getUser();
  if (error || !user) return {status:'signed-out'} as const;
  const member = await db.from('hub_tenant_members').select('tenant_id,role')
    .eq('user_id',user.id).eq('status','active').maybeSingle();
  if (member.error || !member.data) return {status:'forbidden'} as const;
  const tenantId = member.data.tenant_id;
  const checks = await Promise.all(['kpi.manage','transport.documents.use'].map(p_permission =>
    db.rpc('hub_has_permission',{p_tenant_id:tenantId,p_permission})));
  const canManage = checks[0].data === true;
  if (!checks.some(check => check.data === true)) return {status:'forbidden'} as const;
  const profileName = user.user_metadata?.full_name ?? user.user_metadata?.name;
  return {status:'ready',db,tenantId,canManage,profileName:typeof profileName === 'string' ? profileName.slice(0,90) : ''} as const;
}
