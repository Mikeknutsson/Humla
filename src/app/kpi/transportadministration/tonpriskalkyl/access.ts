import 'server-only';

import {reviewAccess} from '@/lib/hub/review-access';

export async function tonPriceAccess() {
  const access = await reviewAccess();
  if (!access) return null;
  const [permission,management,{data:{user}}] = await Promise.all([
    access.db.rpc('hub_can_use_ton_price',{p_tenant_id:access.tenantId}),
    access.db.rpc('hub_has_permission',{p_tenant_id:access.tenantId,p_permission:'kpi.manage'}),
    access.db.auth.getUser(),
  ]);
  if (permission.error || permission.data !== true || !user) return null;
  return {...access,userId:user.id,canManage:management.data === true};
}
